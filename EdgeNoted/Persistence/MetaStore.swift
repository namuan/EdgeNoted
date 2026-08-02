import Foundation
import SwiftData

/// Read/write helpers for local-only metadata. Views query SwiftData with
/// @Query and call these to mutate; the shared ModelContext keeps queries
/// fresh automatically.
@MainActor
enum MetaStore {
    // MARK: Notes

    static func noteMeta(_ noteID: String, in context: ModelContext) -> NoteMeta? {
        let descriptor = FetchDescriptor<NoteMeta>(predicate: #Predicate { $0.noteID == noteID })
        return try? context.fetch(descriptor).first
    }

    static func noteMeta(createIfNeededFor noteID: String, folderID: String, in context: ModelContext) -> NoteMeta {
        if let existing = noteMeta(noteID, in: context) {
            return existing
        }
        let meta = NoteMeta(
            noteID: noteID,
            folderID: folderID,
            orderIndex: nextNoteOrderIndex(folderID: folderID, in: context)
        )
        context.insert(meta)
        try? context.save()
        return meta
    }

    /// One-time migration for rows created before folder IDs were stored: rows
    /// whose folderID is still a folder NAME are re-homed to the real folder
    /// ID, and rows whose folderID is neither a known ID nor a known name are
    /// re-homed to the "All Notes" bucket so no user-visible folder names are
    /// retained. Idempotent and cheap after the first run.
    static func migrateFolderNameKeys(_ folders: [NotesFolder], in context: ModelContext) {
        guard !folders.isEmpty else { return }
        // Duplicate folder names resolve to the first matching folder's ID.
        let idByName = Dictionary(folders.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let knownIDs = Set(folders.map(\.id))
        let metas = (try? context.fetch(FetchDescriptor<NoteMeta>())) ?? []
        var changed = false
        for meta in metas {
            let current = meta.folderID
            if current.isEmpty { continue }
            // A real folder ID always wins, even when it happens to equal a
            // folder name.
            if knownIDs.contains(current) { continue }
            if let id = idByName[current] {
                // Legacy name key -> real folder ID.
                meta.folderID = id
                changed = true
            } else {
                // Stale name for a deleted/nested folder -> All Notes bucket.
                meta.folderID = ""
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }

    static func setNotePinned(_ pinned: Bool, noteID: String, folderID: String, in context: ModelContext) {
        let meta = noteMeta(createIfNeededFor: noteID, folderID: folderID, in: context)
        meta.isPinned = pinned
        try? context.save()
    }

    static func setNoteFolded(_ folded: Bool, noteID: String, folderID: String, in context: ModelContext) {
        let meta = noteMeta(createIfNeededFor: noteID, folderID: folderID, in: context)
        meta.isFolded = folded
        try? context.save()
    }

    static func setNoteColor(_ colorHex: String?, noteID: String, folderID: String, in context: ModelContext) {
        let meta = noteMeta(createIfNeededFor: noteID, folderID: folderID, in: context)
        meta.colorHex = colorHex
        try? context.save()
    }

    static func moveNote(noteID: String, folderID: String, to newIndex: Int, in context: ModelContext) {
        let metas = orderedNoteMetas(folderID: folderID, in: context)
            .filter { $0.noteID != noteID }
        guard metas.indices.contains(newIndex) else { return }
        let meta = noteMeta(createIfNeededFor: noteID, folderID: folderID, in: context)
        var reordered = metas
        reordered.insert(meta, at: newIndex)
        for (index, item) in reordered.enumerated() {
            item.orderIndex = index
        }
        try? context.save()
    }

    static func orderedNoteMetas(folderID: String, in context: ModelContext) -> [NoteMeta] {
        let descriptor = FetchDescriptor<NoteMeta>(
            predicate: #Predicate { $0.folderID == folderID },
            sortBy: [SortDescriptor(\NoteMeta.orderIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func nextNoteOrderIndex(folderID: String, in context: ModelContext) -> Int {
        orderedNoteMetas(folderID: folderID, in: context).count
    }

    // MARK: Folders

    static func folderMeta(_ folderID: String, in context: ModelContext) -> FolderMeta? {
        let descriptor = FetchDescriptor<FolderMeta>(predicate: #Predicate { $0.folderID == folderID })
        return try? context.fetch(descriptor).first
    }

    static func folderMeta(createIfNeededFor folderID: String, in context: ModelContext) -> FolderMeta {
        if let existing = folderMeta(folderID, in: context) {
            return existing
        }
        let meta = FolderMeta(folderID: folderID, orderIndex: nextFolderOrderIndex(in: context))
        context.insert(meta)
        try? context.save()
        return meta
    }

    static func setFolderPinned(_ pinned: Bool, folderID: String, in context: ModelContext) {
        let meta = folderMeta(createIfNeededFor: folderID, in: context)
        meta.isPinned = pinned
        try? context.save()
    }

    static func setFolderColor(_ colorHex: String?, folderID: String, in context: ModelContext) {
        let meta = folderMeta(createIfNeededFor: folderID, in: context)
        meta.colorHex = colorHex
        try? context.save()
    }

    static func orderedFolderMetas(in context: ModelContext) -> [FolderMeta] {
        let descriptor = FetchDescriptor<FolderMeta>(sortBy: [SortDescriptor(\FolderMeta.orderIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func nextFolderOrderIndex(in context: ModelContext) -> Int {
        orderedFolderMetas(in: context).count
    }

    // MARK: Snippets

    static func addSnippet(title: String, text: String, in context: ModelContext) {
        let snippet = Snippet(title: title, text: text)
        context.insert(snippet)
        try? context.save()
    }

    static func deleteSnippet(_ snippet: Snippet, in context: ModelContext) {
        context.delete(snippet)
        try? context.save()
    }
}
