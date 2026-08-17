import Foundation

/// Local-only metadata for a note from Apple Notes. The note's content itself
/// is never stored locally - Apple Notes remains the source of truth.
struct NoteMeta: Codable, Equatable, Identifiable, Sendable {
    var id: String { noteID }

    var noteID: String
    var folderID: String
    // Reserved metadata, kept in the on-disk format for stability even though
    // no UI drives it yet.
    var isPinned: Bool
    var orderIndex: Int
    var isFolded: Bool
    var colorHex: String?
    var lastOpenedAt: Date?

    init(
        noteID: String,
        folderID: String = "",
        isPinned: Bool = false,
        orderIndex: Int = 0,
        isFolded: Bool = false,
        colorHex: String? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.noteID = noteID
        self.folderID = folderID
        self.isPinned = isPinned
        self.orderIndex = orderIndex
        self.isFolded = isFolded
        self.colorHex = colorHex
        self.lastOpenedAt = lastOpenedAt
    }
}
