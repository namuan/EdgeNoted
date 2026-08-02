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
        let meta = NoteMeta(noteID: "note-1", folderID: "folder-1", isPinned: true, orderIndex: 3, colorHex: "FF0000")
        context.insert(meta)
        try context.save()

        let fetched = try MetaStore.noteMeta("note-1", in: context)
        #expect(fetched?.isPinned == true)
        #expect(fetched?.orderIndex == 3)
        #expect(fetched?.colorHex == "FF0000")
    }

    @Test("Create-if-needed does not duplicate by unique noteID")
    func uniqueNoteID() throws {
        let context = makeContext()
        let first = MetaStore.noteMeta(createIfNeededFor: "n1", folderID: "f1", in: context)
        let second = MetaStore.noteMeta(createIfNeededFor: "n1", folderID: "f1", in: context)
        #expect(first === second)
    }

    @Test("Pinning then querying reflects the change")
    func pinning() throws {
        let context = makeContext()
        MetaStore.setNotePinned(true, noteID: "n1", folderID: "f1", in: context)
        #expect(MetaStore.noteMeta("n1", in: context)?.isPinned == true)
        MetaStore.setNotePinned(false, noteID: "n1", folderID: "f1", in: context)
        #expect(MetaStore.noteMeta("n1", in: context)?.isPinned == false)
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

    @Test("Snippets are stored and can be deleted")
    func snippets() throws {
        let context = makeContext()
        MetaStore.addSnippet(title: "Greeting", text: "Hi there", in: context)
        let all = (try context.fetch(FetchDescriptor<Snippet>())) ?? []
        #expect(all.count == 1)
        MetaStore.deleteSnippet(all[0], in: context)
        #expect(((try context.fetch(FetchDescriptor<Snippet>())) ?? []).isEmpty)
    }
}
