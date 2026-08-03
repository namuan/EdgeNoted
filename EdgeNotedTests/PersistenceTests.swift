import SwiftData
import Testing

@testable import EdgeNoted

@Suite("SwiftData persistence (in-memory)", .serialized)
@MainActor
struct PersistenceTests {
    /// One shared in-memory container for the whole suite. Each test works in
    /// its own fresh ModelContext, avoiding the SwiftData teardown trap that
    /// occurs when many containers are created and deallocated in parallel.
    private static let container: ModelContainer = {
        do {
            return try PersistenceController.inMemoryContainer()
        } catch {
            fatalError("Failed to create in-memory container: \(error)")
        }
    }()

    private func makeContext() -> ModelContext {
        ModelContext(Self.container)
    }

    @Test("NoteMeta round-trips through the store")
    func noteMetaRoundTrip() throws {
        let context = makeContext()
        let meta = NoteMeta(noteID: "note-1", folderID: "folder-1", orderIndex: 3)
        context.insert(meta)
        try context.save()

        let fetched = MetaStore.noteMeta("note-1", in: context)
        #expect(fetched?.orderIndex == 3)
    }

    @Test("Create-if-needed does not duplicate by unique noteID")
    func uniqueNoteID() throws {
        let context = makeContext()
        let first = MetaStore.noteMeta(createIfNeededFor: "n1", folderID: "f1", in: context)
        let second = MetaStore.noteMeta(createIfNeededFor: "n1", folderID: "f1", in: context)
        #expect(first === second)
    }

    @Test("Move updates the local ordering of the folder")
    func reordering() throws {
        let context = makeContext()
        for index in 0..<3 {
            _ = MetaStore.noteMeta(createIfNeededFor: "note-\(index)", folderID: "f1", in: context)
        }
        MetaStore.moveNote(noteID: "note-2", folderID: "f1", to: 0, in: context)
        let ordered = MetaStore.orderedNoteMetas(folderID: "f1", in: context).map(\.noteID)
        #expect(ordered[0] == "note-2")
    }

    @Test("Folder-name metadata keys migrate to real folder IDs")
    func migrateFolderNameKeys() throws {
        let context = makeContext()
        // Legacy rows created before folder IDs were stored.
        let legacy = NoteMeta(noteID: "legacy", folderID: "Concepts")
        context.insert(legacy)
        let fresh = NoteMeta(noteID: "fresh", folderID: "f-1")
        context.insert(fresh)
        // A stale name for a folder that no longer exists.
        let stale = NoteMeta(noteID: "stale", folderID: "Gone Folder")
        context.insert(stale)
        try context.save()

        let folders = [NotesFolder(id: "f-1", name: "Concepts")]
        MetaStore.migrateFolderNameKeys(folders, in: context)

        #expect(MetaStore.noteMeta("legacy", in: context)?.folderID == "f-1")
        #expect(MetaStore.noteMeta("fresh", in: context)?.folderID == "f-1")
        #expect(MetaStore.noteMeta("stale", in: context)?.folderID == "")
    }

    @Test("Migration survives duplicate folder names and name/id collisions")
    func migrateEdgeCases() throws {
        let context = makeContext()
        let byName = NoteMeta(noteID: "by-name", folderID: "Concepts")
        context.insert(byName)
        let byID = NoteMeta(noteID: "by-id", folderID: "f-2")
        context.insert(byID)
        try context.save()

        // Two folders named "Concepts" (duplicate) and a folder whose name
        // collides with another folder's real ID.
        let folders = [
            NotesFolder(id: "f-1", name: "Concepts"),
            NotesFolder(id: "f-2", name: "Concepts"),
            NotesFolder(id: "f-3", name: "f-2"),
        ]
        MetaStore.migrateFolderNameKeys(folders, in: context)

        // Duplicate names: first wins.
        #expect(MetaStore.noteMeta("by-name", in: context)?.folderID == "f-1")
        // A real ID that also equals a folder name must not be re-homed.
        #expect(MetaStore.noteMeta("by-id", in: context)?.folderID == "f-2")
    }
}
