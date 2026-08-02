import Foundation
import SwiftData

/// Local-only metadata for a note from Apple Notes. The note's content itself
/// is never stored locally - Apple Notes remains the source of truth.
@Model
final class NoteMeta {
    @Attribute(.unique) var noteID: String
    var folderID: String
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

/// Local-only metadata for a Notes folder.
@Model
final class FolderMeta {
    @Attribute(.unique) var folderID: String
    var isPinned: Bool
    var orderIndex: Int
    var colorHex: String?

    init(folderID: String, isPinned: Bool = false, orderIndex: Int = 0, colorHex: String? = nil) {
        self.folderID = folderID
        self.isPinned = isPinned
        self.orderIndex = orderIndex
        self.colorHex = colorHex
    }
}

/// A reusable text snippet managed in EdgeNoted.
@Model
final class Snippet {
    var title: String
    var text: String
    var createdAt: Date

    init(title: String, text: String, createdAt: Date = .now) {
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }
}
