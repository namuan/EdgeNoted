import Testing

@testable import EdgeNoted

@Suite("Note draft synchronization state machine")
struct NoteDraftSyncTests {
    @Test("Loading a note starts clean")
    func loadStartsClean() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        #expect(sync.state == .clean(remoteHash: NoteDraftSync.hash(of: "hello")))
        #expect(!sync.isDirty)
    }

    @Test("Editing marks the draft dirty")
    func editMarksDirty() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "hello world")
        #expect(sync.isDirty)
        #expect(!sync.isInConflict)
    }

    @Test("Reverting to the remote text clears the dirty flag")
    func revertClearsDirty() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "hello!")
        sync.edit(localBody: "hello")
        #expect(!sync.isDirty)
    }

    @Test("Submitting a draft returns to clean")
    func submitCleans() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "hello v2")
        sync.submitted(localBody: "hello v2")
        #expect(sync.state == .clean(remoteHash: NoteDraftSync.hash(of: "hello v2")))
        #expect(!sync.isDirty)
    }

    @Test("A remote echo of our own write is not a change")
    func ownWriteEchoSuppressed() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "hello v2")
        sync.submitted(localBody: "hello v2")
        let event = sync.observeRemote(body: "hello v2")
        #expect(event == .noChange)
    }

    @Test("Remote change on a clean draft is adopted safely")
    func remoteChangeOnCleanDraft() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        let event = sync.observeRemote(body: "hello from Notes")
        #expect(event == .remoteUpdated(body: "hello from Notes"))
        #expect(!sync.isDirty)
    }

    @Test("Remote change while dirty becomes a conflict")
    func remoteChangeWhileDirtyConflicts() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "my local edit")
        let event = sync.observeRemote(body: "changed elsewhere")
        #expect(event == .conflict(remoteBody: "changed elsewhere"))
        #expect(sync.isInConflict)
        #expect(sync.isDirty)
    }

    @Test("Resolving keep-mine forces a push")
    func resolveKeepMine() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "my edit")
        _ = sync.observeRemote(body: "theirs")
        sync.resolveKeepingLocal(localBody: "my edit")
        #expect(!sync.isInConflict)
        #expect(sync.isDirty)
        sync.submitted(localBody: "my edit")
        #expect(!sync.isDirty)
    }

    @Test("Resolving take-theirs adopts the remote content")
    func resolveTakeRemote() {
        var sync = NoteDraftSync()
        sync.load(remoteBody: "hello")
        sync.edit(localBody: "my edit")
        _ = sync.observeRemote(body: "theirs")
        sync.resolveTakingRemote(body: "theirs")
        #expect(!sync.isDirty)
        #expect(!sync.isInConflict)
        let event = sync.observeRemote(body: "theirs")
        #expect(event == .noChange)
    }

    @Test("Hashing is deterministic and sensitive to changes")
    func hashing() {
        #expect(NoteDraftSync.hash(of: "abc") == NoteDraftSync.hash(of: "abc"))
        #expect(NoteDraftSync.hash(of: "abc") != NoteDraftSync.hash(of: "abd"))
        #expect(!NoteDraftSync.hash(of: "").isEmpty)
    }
}
