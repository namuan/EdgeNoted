import Foundation
import Testing

@testable import EdgeNoted

@Suite("MetaStore persistence (in-memory)")
@MainActor
struct PersistenceTests {
    private func makeStore() -> MetaStore {
        PersistenceController.makeInMemoryStore()
    }

    @Test("NoteMeta round-trips through the store")
    func noteMetaRoundTrip() {
        let store = makeStore()
        store.insert(NoteMeta(noteID: "note-1", folderID: "folder-1", orderIndex: 3))
        #expect(store.noteMeta("note-1")?.orderIndex == 3)
    }

    @Test("Create-if-needed does not duplicate by unique noteID")
    func uniqueNoteID() {
        let store = makeStore()
        let first = store.noteMeta(createIfNeededFor: "n1", folderID: "f1")
        let second = store.noteMeta(createIfNeededFor: "n1", folderID: "f1")
        #expect(first == second)
        #expect(store.noteMeta("n1") == first)
    }

    @Test("Move updates the local ordering of the folder")
    func reordering() {
        let store = makeStore()
        for index in 0..<3 {
            _ = store.noteMeta(createIfNeededFor: "note-\(index)", folderID: "f1")
        }
        store.moveNote(noteID: "note-2", folderID: "f1", to: 0)
        let ordered = store.orderedNoteMetas(folderID: "f1").map(\.noteID)
        #expect(ordered[0] == "note-2")
    }

    @Test("Folder-name metadata keys migrate to real folder IDs")
    func migrateFolderNameKeys() {
        let store = makeStore()
        // Legacy rows created before folder IDs were stored.
        store.insert(NoteMeta(noteID: "legacy", folderID: "Concepts"))
        store.insert(NoteMeta(noteID: "fresh", folderID: "f-1"))
        // A stale name for a folder that no longer exists.
        store.insert(NoteMeta(noteID: "stale", folderID: "Gone Folder"))

        let folders = [NotesFolder(id: "f-1", name: "Concepts")]
        store.migrateFolderNameKeys(folders)

        #expect(store.noteMeta("legacy")?.folderID == "f-1")
        #expect(store.noteMeta("fresh")?.folderID == "f-1")
        #expect(store.noteMeta("stale")?.folderID == "")
    }

    @Test("Migration survives duplicate folder names and name/id collisions")
    func migrateEdgeCases() {
        let store = makeStore()
        store.insert(NoteMeta(noteID: "by-name", folderID: "Concepts"))
        store.insert(NoteMeta(noteID: "by-id", folderID: "f-2"))

        // Two folders named "Concepts" (duplicate) and a folder whose name
        // collides with another folder's real ID.
        let folders = [
            NotesFolder(id: "f-1", name: "Concepts"),
            NotesFolder(id: "f-2", name: "Concepts"),
            NotesFolder(id: "f-3", name: "f-2"),
        ]
        store.migrateFolderNameKeys(folders)

        // Duplicate names: first wins.
        #expect(store.noteMeta("by-name")?.folderID == "f-1")
        // A real ID that also equals a folder name must not be re-homed.
        #expect(store.noteMeta("by-id")?.folderID == "f-2")
    }

    @Test("Changes persist to disk and reload into a new store")
    func persistsToDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("metadata.json")

        let store = MetaStore(fileURL: url)
        store.insert(NoteMeta(noteID: "n1", folderID: "f1", isPinned: true, orderIndex: 2))
        let openedAt = Date(timeIntervalSince1970: 1_234_567)
        store.update("n1") { $0.lastOpenedAt = openedAt }

        let reloaded = MetaStore(fileURL: url)
        #expect(reloaded.noteMeta("n1")?.folderID == "f1")
        #expect(reloaded.noteMeta("n1")?.orderIndex == 2)
        #expect(reloaded.noteMeta("n1")?.isPinned == true)
        #expect(reloaded.noteMeta("n1")?.lastOpenedAt == openedAt)
    }

    @Test("A corrupt file falls back to an empty store")
    func corruptFileFallsBackToEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetaStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("metadata.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = MetaStore(fileURL: url)
        #expect(store.noteMeta("anything") == nil)
    }
}
