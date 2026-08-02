/// What a poll observed on the remote (Apple Notes) side.
enum RemoteEvent: Equatable, Sendable {
    case noChange
    /// The remote changed while the local draft was clean; safe to adopt.
    case remoteUpdated(body: String)
    /// The remote changed while the local draft had unsaved edits.
    case conflict(remoteBody: String)
}

/// Pure synchronization state machine for a single note.
///
/// Apple Notes is the source of truth. EdgeNoted keeps a local draft and must
/// never silently overwrite remote changes made while the user has unsaved
/// local edits - those surface as conflicts the user resolves explicitly.
struct NoteDraftSync: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case clean(remoteHash: String)
        case dirty(remoteHash: String, localHash: String)
        case conflict(remoteHash: String, localHash: String)
    }

    private(set) var state: State = .idle

    var isDirty: Bool {
        switch state {
        case .dirty, .conflict: true
        case .idle, .clean: false
        }
    }

    var isInConflict: Bool {
        if case .conflict = state { return true }
        return false
    }

    /// Stable FNV-1a hash used only for change comparison, never persisted.
    static func hash(of text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Called when a note is opened: local draft is the remote body.
    mutating func load(remoteBody: String) {
        state = .clean(remoteHash: Self.hash(of: remoteBody))
    }

    /// Called on every local keystroke.
    mutating func edit(localBody: String) {
        let localHash = Self.hash(of: localBody)
        switch state {
        case .idle:
            break
        case .clean(let remoteHash):
            state =
                localHash == remoteHash
                ? .clean(remoteHash: remoteHash)
                : .dirty(remoteHash: remoteHash, localHash: localHash)
        case .dirty(let remoteHash, _):
            state =
                localHash == remoteHash
                ? .clean(remoteHash: remoteHash)
                : .dirty(remoteHash: remoteHash, localHash: localHash)
        case .conflict(let remoteHash, _):
            state = .conflict(remoteHash: remoteHash, localHash: localHash)
        }
    }

    /// Called after a successful remote write of the local draft.
    mutating func submitted(localBody: String) {
        let localHash = Self.hash(of: localBody)
        switch state {
        case .dirty, .conflict:
            state = .clean(remoteHash: localHash)
        case .idle, .clean:
            break
        }
    }

    /// Called when a poll observes remote content.
    mutating func observeRemote(body: String) -> RemoteEvent {
        let remoteHash = Self.hash(of: body)
        switch state {
        case .idle:
            state = .clean(remoteHash: remoteHash)
            return .noChange
        case .clean(let knownRemote):
            if remoteHash == knownRemote { return .noChange }
            state = .clean(remoteHash: remoteHash)
            return .remoteUpdated(body: body)
        case .dirty(let knownRemote, let localHash):
            // Echo of our own submitted write is not a conflict.
            if remoteHash == knownRemote { return .noChange }
            state = .conflict(remoteHash: remoteHash, localHash: localHash)
            return .conflict(remoteBody: body)
        case .conflict(let knownRemote, let localHash):
            if remoteHash == knownRemote { return .conflict(remoteBody: body) }
            state = .conflict(remoteHash: remoteHash, localHash: localHash)
            return .conflict(remoteBody: body)
        }
    }

    /// User chose "keep mine": push local over the remote.
    mutating func resolveKeepingLocal(localBody: String) {
        let localHash = Self.hash(of: localBody)
        state = .dirty(remoteHash: localHash, localHash: localHash)
    }

    /// User chose "take theirs": adopt the remote content.
    mutating func resolveTakingRemote(body: String) {
        state = .clean(remoteHash: Self.hash(of: body))
    }
}
