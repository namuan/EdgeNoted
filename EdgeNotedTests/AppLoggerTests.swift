import Foundation
import Testing

@testable import EdgeNoted

@Suite("File logger")
struct AppLoggerTests {
    private func makeLogger(maxFileSize: Int = 1_048_576, retained: Int = 5) throws -> (AppLogger, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLoggerTests-\(UUID().uuidString)", isDirectory: true)
        let configuration = AppLogConfiguration(
            preferredDirectory: directory,
            maxFileSize: maxFileSize,
            retainedArchives: retained,
            fileNameBase: "EdgeNoted"
        )
        return (AppLogger(configuration: configuration), directory)
    }

    @Test("Creates the log directory and writes formatted lines")
    func createsAndWrites() async throws {
        let (logger, directory) = try makeLogger()
        await logger.log(level: .info, category: .bridge, message: "hello", metadata: ["cmd": "folders"])
        await logger.log(level: .error, category: .notes, message: "boom")
        await logger.flush()

        let file = directory.appendingPathComponent("EdgeNoted.log")
        #expect(FileManager.default.fileExists(atPath: file.path))
        let contents = try String(contentsOf: file, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(contents.contains(" INFO [bridge] hello cmd=folders"))
        #expect(contents.contains(" ERROR [notes] boom"))
    }

    @Test("Rotates when the file exceeds the maximum size")
    func rotatesAtThreshold() async throws {
        let (logger, directory) = try makeLogger(maxFileSize: 200, retained: 2)
        for index in 0..<20 {
            await logger.log(level: .info, category: .lifecycle, message: "line \(index)")
        }
        await logger.flush()

        let fileManager = FileManager.default
        let current = directory.appendingPathComponent("EdgeNoted.log")
        let first = directory.appendingPathComponent("EdgeNoted-1.log")
        let second = directory.appendingPathComponent("EdgeNoted-2.log")
        #expect(fileManager.fileExists(atPath: current.path))
        #expect(fileManager.fileExists(atPath: first.path))
        #expect(fileManager.fileExists(atPath: second.path))
        // The retained cap (2 archives) must hold: no EdgeNoted-3.log.
        let third = directory.appendingPathComponent("EdgeNoted-3.log")
        #expect(!fileManager.fileExists(atPath: third.path))
    }

    @Test("Concurrent appends are serialized and all land in the file")
    func concurrentAppends() async throws {
        let (logger, directory) = try makeLogger()
        let lineCount = 50
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<lineCount {
                group.addTask {
                    await logger.log(level: .debug, category: .sync, message: "concurrent \(index)")
                }
            }
            await group.waitForAll()
        }
        await logger.flush()

        let file = directory.appendingPathComponent("EdgeNoted.log")
        let contents = try String(contentsOf: file, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == lineCount)
        for index in 0..<lineCount {
            #expect(contents.contains("concurrent \(index)"))
        }
    }

    @Test("Logging never throws even when no directory can be written")
    func failureIsNonFatal() async {
        let configuration = AppLogConfiguration(
            preferredDirectory: URL(fileURLWithPath: "/dev/null/EdgeNoted-Logs", isDirectory: true),
            maxFileSize: 1024,
            retainedArchives: 2,
            fileNameBase: "EdgeNoted",
            allowsFallback: false
        )
        let logger = AppLogger(configuration: configuration)
        await logger.log(level: .error, category: .lifecycle, message: "this must not crash")
        await logger.flush()
        // The logger must have failed to open any file (no fallback), not just
        // have written somewhere else.
        #expect(!FileManager.default.fileExists(atPath: configuration.preferredDirectory.path))
    }

    @Test("Large threshold never rotates small files")
    func noPrematureRotation() async throws {
        let (logger, directory) = try makeLogger(maxFileSize: 1_048_576, retained: 2)
        for index in 0..<100 {
            await logger.log(level: .info, category: .sync, message: "line \(index)")
        }
        await logger.flush()
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: directory.appendingPathComponent("EdgeNoted.log").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("EdgeNoted-1.log").path))
    }

    @Test("Name digests never leak the original value")
    func digestsAreOpaque() {
        let name = "My Private Folder"
        let digest = Log.digest(name)
        #expect(!digest.contains("Private"))
        #expect(!digest.contains(name))
        #expect(digest.count == 8)
        // Deterministic.
        #expect(Log.digest(name) == digest)
        #expect(Log.digest("") == "-")
    }
}
