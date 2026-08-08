import Foundation

/// Log severity levels.
enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Broad functional area used to group log lines.
enum LogCategory: String, Sendable {
    case lifecycle
    case windowing
    case notes
    case reminders
    case bridge
    case sync
    case settings
    case export
    case persistence
}

/// Immutable configuration for the file logger.
struct AppLogConfiguration: Sendable {
    /// Preferred directory, `~/Library/Logs/EdgeNoted`. Resolved against the
    /// real home directory (NSHomeDirectoryForUser), not the sandbox container.
    let preferredDirectory: URL
    /// Maximum size of the current log file before it rotates (bytes).
    let maxFileSize: Int
    /// How many rotated archives to keep (the current file is extra).
    let retainedArchives: Int
    /// Base file name used for the current and archive files.
    let fileNameBase: String
    /// When false, never fall back to the app container log directory (used by
    /// tests so a deliberately failing logger cannot touch real logs).
    let allowsFallback: Bool

    static let `default` = AppLogConfiguration(
        preferredDirectory: URL(
            fileURLWithPath: (NSHomeDirectoryForUser(nil) ?? NSHomeDirectory())
                + "/Library/Logs/EdgeNoted",
            isDirectory: true
        ),
        maxFileSize: 1_048_576,
        retainedArchives: 5,
        fileNameBase: "EdgeNoted",
        allowsFallback: true
    )

    init(
        preferredDirectory: URL,
        maxFileSize: Int,
        retainedArchives: Int,
        fileNameBase: String,
        allowsFallback: Bool = true
    ) {
        self.preferredDirectory = preferredDirectory
        self.maxFileSize = maxFileSize
        self.retainedArchives = max(retainedArchives, 1)
        self.fileNameBase = fileNameBase
        self.allowsFallback = allowsFallback
    }
}

/// File-based logger with size-based rolling log files.
///
/// Writes lines like `2026-08-02 20:10:00.123 INFO [bridge] command=folders
/// args=0 elapsedMs=42 status=0` to `EdgeNoted.log` in `~/Library/Logs/EdgeNoted`.
/// When the current file exceeds `maxFileSize` it is renamed to `EdgeNoted-1.log`
/// and older archives shift up to the retained cap.
///
/// If the preferred directory cannot be created (e.g. a sandbox denial) the
/// logger falls back to the app container's `Library/Logs/EdgeNoted`. Logging
/// failures are never fatal.
actor AppLogger {
    static let shared = AppLogger(configuration: .default)

    private let configuration: AppLogConfiguration
    private var activeDirectory: URL?
    private var currentFileURL: URL?
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0
    private var isSetup = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(configuration: AppLogConfiguration) {
        self.configuration = configuration
    }

    /// The directory logs are actually being written to, once setup has run.
    func activeDirectoryPath() async -> String? {
        await setupIfNeeded()
        return activeDirectory?.path
    }

    func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String] = [:]
    ) async {
        await setupIfNeeded()

        let line = Self.formattedLine(
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        let lineData = Data(line.utf8)

        if currentSize + UInt64(lineData.count) > UInt64(configuration.maxFileSize) {
            await rotate()
        }
        guard let fileHandle = self.handle else { return }

        fileHandle.write(lineData)
        currentSize += UInt64(lineData.count)
    }

    /// Flushes pending writes to disk.
    func flush() async {
        try? handle?.synchronize()
    }

    /// Closes the current file handle.
    func close() async {
        handle?.closeFile()
        handle = nil
    }

    // MARK: - Setup

    private func setupIfNeeded() async {
        guard !isSetup else { return }
        isSetup = true

        let fileManager = FileManager.default
        if let directory = Self.createDirectory(at: configuration.preferredDirectory, fileManager: fileManager) {
            activeDirectory = directory
        } else if configuration.allowsFallback,
            let fallback = Self.containerLogDirectory(fileManager: fileManager),
            let directory = Self.createDirectory(at: fallback, fileManager: fileManager)
        {
            activeDirectory = directory
        }
        guard let activeDirectory else { return }

        currentFileURL = activeDirectory.appendingPathComponent("\(configuration.fileNameBase).log")
        guard let currentFileURL else { return }
        if !fileManager.fileExists(atPath: currentFileURL.path) {
            fileManager.createFile(atPath: currentFileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: currentFileURL)
        if let handle {
            currentSize = handle.seekToEndOfFile()
        }
        // Only the production logger announces itself, so test loggers with
        // their own directories never write into the real log.
        if ObjectIdentifier(self) == ObjectIdentifier(AppLogger.shared) {
            Log.info("Log file opened", category: .persistence, metadata: ["path": activeDirectory.path])
        }
    }

    private static func createDirectory(at url: URL, fileManager: FileManager) -> URL? {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }

    /// Fallback location when the preferred directory is not writable: the
    /// sandbox container's Library/Logs/EdgeNoted.
    private static func containerLogDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/EdgeNoted", isDirectory: true)
    }

    // MARK: - Rotation

    private func rotate() async {
        let triggeredAt = currentSize
        handle?.closeFile()
        handle = nil

        let fileManager = FileManager.default
        guard let activeDirectory, let currentFileURL else { return }
        Log.info(
            "Log file rotated",
            category: .persistence,
            metadata: [
                "maxFileSize": String(configuration.maxFileSize),
                "triggeredAt": String(triggeredAt),
                "path": activeDirectory.path,
            ]
        )
        let base = configuration.fileNameBase
        let retained = configuration.retainedArchives

        // Delete the oldest archive (EdgeNoted-{retained}.log).
        let oldest = activeDirectory.appendingPathComponent("\(base)-\(retained).log")
        try? fileManager.removeItem(at: oldest)

        // Shift EdgeNoted-{retained-1}...EdgeNoted-1 up one slot.
        if retained > 1 {
            for index in stride(from: retained - 1, through: 1, by: -1) {
                let source = activeDirectory.appendingPathComponent("\(base)-\(index).log")
                let destination = activeDirectory.appendingPathComponent("\(base)-\(index + 1).log")
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.moveItem(at: source, to: destination)
                }
            }
        }

        // Move the current file to EdgeNoted-1.log and start a fresh one.
        let first = activeDirectory.appendingPathComponent("\(base)-1.log")
        try? fileManager.removeItem(at: first)
        try? fileManager.moveItem(at: currentFileURL, to: first)

        fileManager.createFile(atPath: currentFileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: currentFileURL)
        handle?.seekToEndOfFile()
        currentSize = 0
    }

    // MARK: - Formatting

    private static func formattedLine(
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String]
    ) -> String {
        let timestamp = dateFormatter.string(from: Date())
        let sanitized =
            message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        var line = "\(timestamp) \(level.rawValue.uppercased()) [\(category.rawValue)] \(sanitized)"
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            let sanitizedValue =
                value
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            line += " \(key)=\(sanitizedValue)"
        }
        return line + "\n"
    }
}

/// Minimal, fire-and-forget logging facade used at call sites that do not need
/// to await the file write. Lifecycle-critical paths can await `Log.event` or
/// call `AppLogger.shared` directly.
enum Log {
    static func info(_ message: String, category: LogCategory = .lifecycle, metadata: [String: String] = [:]) {
        emit(level: .info, message: message, category: category, metadata: metadata)
    }

    static func warning(_ message: String, category: LogCategory = .lifecycle, metadata: [String: String] = [:]) {
        emit(level: .warning, message: message, category: category, metadata: metadata)
    }

    static func error(_ message: String, category: LogCategory = .lifecycle, metadata: [String: String] = [:]) {
        emit(level: .error, message: message, category: category, metadata: metadata)
    }

    /// Awaited variant for critical paths (app launch/termination).
    static func event(level: LogLevel, category: LogCategory, message: String, metadata: [String: String] = [:]) async {
        await AppLogger.shared.log(level: level, category: category, message: message, metadata: metadata)
    }

    /// Synchronous, nonisolated flush-and-close for app termination. Must be
    /// called from a non-MainActor context so the semaphore wait never blocks
    /// the actor the work itself needs.
    nonisolated static func closeSynchronously() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await AppLogger.shared.flush()
            await AppLogger.shared.close()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    /// A short, stable digest used instead of raw user-visible names (folder
    /// names, list names) so logs never contain potentially sensitive titles.
    static func digest(_ value: String) -> String {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return "-" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16).prefix(8).description
    }

    private static func emit(level: LogLevel, message: String, category: LogCategory, metadata: [String: String]) {
        Task {
            await AppLogger.shared.log(level: level, category: category, message: message, metadata: metadata)
        }
    }
}
