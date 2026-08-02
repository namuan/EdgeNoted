import Foundation

// MARK: - Data types

struct NotesFolder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct NoteSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct NoteDetail: Identifiable, Sendable {
    let id: String
    let name: String
    let body: String
    let modificationEpoch: TimeInterval?
}

// MARK: - Protocol

/// Bridge to Apple Notes. Implementations must be Sendable and safe to call
/// from any actor; the executor serializes the actual Apple Events.
protocol NotesService: Sendable {
    func fetchFolders() async throws -> [NotesFolder]
    /// `folderName` nil returns every note; otherwise the notes directly
    /// inside that folder.
    func fetchNotes(folderName: String?) async throws -> [NoteSummary]
    func fetchNote(id: String) async throws -> NoteDetail
    func searchNotes(query: String) async throws -> [NoteSummary]
    func createNote(title: String, body: String, folderName: String?) async throws -> NoteDetail
    func updateNote(id: String, title: String, body: String) async throws
}

// MARK: - AppleScript implementation

/// NotesService backed by the Apple Notes AppleScript dictionary.
final class AppleScriptNotesService: NotesService, @unchecked Sendable {
    private let executor: AppleScriptExecutor

    init(executor: AppleScriptExecutor = .shared) {
        self.executor = executor
    }

    func fetchFolders() async throws -> [NotesFolder] {
        try await logged("fetchFolders") {
            let output = try await executor.run(command: "folders")
            let entries = try decode([FolderEntry].self, from: output)
            return entries.map { NotesFolder(id: $0.idStr, name: $0.nameStr) }
        }
    }

    func fetchNotes(folderName: String?) async throws -> [NoteSummary] {
        try await logged("fetchNotes") {
            let output = try await executor.run(command: "notes", arguments: [folderName ?? "ALL"])
            let entries = try decode([NoteListEntry].self, from: output)
            return entries.map { NoteSummary(id: $0.idStr, name: $0.nameStr) }
        }
    }

    func fetchNote(id: String) async throws -> NoteDetail {
        try await logged("fetchNote", noteID: id) {
            let output = try await executor.run(command: "note", arguments: [id])
            let entry = try decode(NoteEntry.self, from: output)
            if let error = entry.errorStr {
                throw ScriptError.executionFailed(error)
            }
            return NoteDetail(
                id: entry.idStr ?? id,
                name: entry.nameStr ?? "Untitled",
                body: entry.bodyStr ?? "",
                modificationEpoch: entry.modEpoch
            )
        }
    }

    func searchNotes(query: String) async throws -> [NoteSummary] {
        try await logged("searchNotes") {
            let output = try await executor.run(command: "search", arguments: [query])
            let entries = try decode([NoteListEntry].self, from: output)
            return entries.map { NoteSummary(id: $0.idStr, name: $0.nameStr) }
        }
    }

    func createNote(title: String, body: String, folderName: String?) async throws -> NoteDetail {
        try await logged("createNote") {
            let output = try await executor.run(command: "create", arguments: [folderName ?? "ALL", title, body])
            let entry = try decode(NoteEntry.self, from: output)
            if let error = entry.errorStr {
                throw ScriptError.executionFailed(error)
            }
            return NoteDetail(id: entry.idStr ?? "", name: entry.nameStr ?? title, body: body, modificationEpoch: nil)
        }
    }

    func updateNote(id: String, title: String, body: String) async throws {
        try await logged("updateNote", noteID: id) {
            let output = try await executor.run(command: "update", arguments: [id, title, body])
            guard output.hasPrefix("OK") else {
                throw ScriptError.executionFailed(output)
            }
        }
    }

    private func logged<T>(_ operation: String, noteID: String? = nil, _ body: () async throws -> T) async throws -> T {
        let startedAt = Date()
        do {
            let result = try await body()
            Log.info(
                "Notes \(operation) ok",
                category: .notes,
                metadata: [
                    "noteId": noteID ?? "-",
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
            return result
        } catch {
            Log.error(
                "Notes \(operation) failed",
                category: .notes,
                metadata: [
                    "noteId": noteID ?? "-",
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
            throw error
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw ScriptError.malformedOutput(output)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ScriptError.malformedOutput(output)
        }
    }

    private struct FolderEntry: Decodable {
        let idStr: String
        let nameStr: String
    }

    private struct NoteListEntry: Decodable {
        let idStr: String
        let nameStr: String
    }

    private struct NoteEntry: Decodable {
        let idStr: String?
        let nameStr: String?
        let bodyStr: String?
        let modEpoch: Double?
        let errorStr: String?
    }
}

// MARK: - Fake implementation (tests / UI tests)

/// In-memory NotesService used by unit tests and UI tests. No Apple Events.
actor FakeNotesService: NotesService {
    private struct StoredNote: Sendable {
        var name: String
        var body: String
        var folderName: String?
        var modificationEpoch: TimeInterval
    }

    private var folders: [NotesFolder]
    private var store: [String: StoredNote]
    /// Monotonic epoch so consecutive writes always change the modification
    /// timestamp (a wall clock can repeat within the same second).
    private var nextEpochValue: TimeInterval
    /// Number of folder fetches, used by tests to verify startup runs once.
    private var foldersFetchCount = 0

    init(
        folders: [NotesFolder] = [
            NotesFolder(id: "f-work", name: "Work"),
            NotesFolder(id: "f-personal", name: "Personal"),
        ]
    ) {
        self.folders = folders
        self.store = [:]
        self.nextEpochValue = 1_000_000
    }

    private func nextEpoch() -> TimeInterval {
        nextEpochValue += 1
        return nextEpochValue
    }

    func seed(id: String, name: String, body: String, folderName: String? = nil) {
        store[id] = StoredNote(name: name, body: body, folderName: folderName, modificationEpoch: nextEpoch())
    }

    func fetchFolders() async throws -> [NotesFolder] {
        foldersFetchCount += 1
        return folders
    }

    var folderFetchCount: Int { foldersFetchCount }

    func fetchNotes(folderName: String?) async throws -> [NoteSummary] {
        store
            .filter { folderName == nil || $0.value.folderName == folderName }
            .map { NoteSummary(id: $0.key, name: $0.value.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchNote(id: String) async throws -> NoteDetail {
        guard let note = store[id] else {
            throw ScriptError.executionFailed("Note not found: \(id)")
        }
        return NoteDetail(id: id, name: note.name, body: note.body, modificationEpoch: note.modificationEpoch)
    }

    func searchNotes(query: String) async throws -> [NoteSummary] {
        store
            .filter { $0.value.name.localizedCaseInsensitiveContains(query) }
            .map { NoteSummary(id: $0.key, name: $0.value.name) }
    }

    func createNote(title: String, body: String, folderName: String?) async throws -> NoteDetail {
        let id = "fake-note-\(store.count + 1)"
        store[id] = StoredNote(name: title, body: body, folderName: folderName, modificationEpoch: nextEpoch())
        return NoteDetail(id: id, name: title, body: body, modificationEpoch: nil)
    }

    func updateNote(id: String, title: String, body: String) async throws {
        guard var note = store[id] else {
            throw ScriptError.executionFailed("Note not found: \(id)")
        }
        note.name = title
        note.body = body
        note.modificationEpoch = nextEpoch()
        store[id] = note
    }

    /// Simulates an external edit (as if made in Apple Notes).
    func simulateExternalEdit(id: String, name: String, body: String) {
        guard var note = store[id] else { return }
        note.name = name
        note.body = body
        note.modificationEpoch = nextEpoch()
        store[id] = note
    }
}
