import Foundation
import Observation

/// Read/write helpers for local-only metadata. Unlike the previous SwiftData
/// store this keeps the full in-memory picture and persists it atomically to
/// a JSON file, so no Xcode-Only macro plugin is needed to build or run it.
@MainActor
@Observable
final class MetaStore {
    /// On-disk encoding of the store contents.
    private struct StoreFile: Codable {
        var version: Int
        var noteMetas: [NoteMeta]
    }

    private var noteMetas: [String: NoteMeta] = [:]
    private let fileURL: URL?

    /// - Parameter fileURL: Where metadata is persisted. Pass `nil` for a
    ///   purely in-memory store (unit tests).
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        load()
        Log.info(
            "Local metadata store ready",
            category: .persistence,
            metadata: [
                "notes": String(noteMetas.count),
                "persisted": fileURL == nil ? "no" : "yes",
            ]
        )
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let file = try JSONDecoder().decode(StoreFile.self, from: data)
            guard file.version == 1 else {
                Log.warning(
                    "Ignoring metadata file with unsupported version",
                    category: .persistence,
                    metadata: ["version": String(file.version)]
                )
                return
            }
            noteMetas = Dictionary(file.noteMetas.map { ($0.noteID, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            // A corrupt or unreadable file is not worth crashing over: the
            // local metadata is only re-creatable ordering/pin bookkeeping.
            Log.warning("Failed to load local metadata; starting fresh", category: .persistence)
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stableOrder = noteMetas.values.sorted {
                $0.folderID != $1.folderID ? $0.folderID < $1.folderID : $0.orderIndex < $1.orderIndex
            }
            let file = StoreFile(version: 1, noteMetas: Array(stableOrder))
            let data = try JSONEncoder().encode(file)
            // .atomic writes to a temp file and renames it into place, so a
            // crash mid-write can never leave a half-written file behind.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.error("Failed to persist local metadata", category: .persistence)
        }
    }

    // MARK: - Notes

    func noteMeta(_ noteID: String) -> NoteMeta? {
        noteMetas[noteID]
    }

    /// Returns the stored metadata for `noteID`, creating it (with an order
    /// index at the end of its folder) when no row exists yet.
    @discardableResult
    func noteMeta(createIfNeededFor noteID: String, folderID: String) -> NoteMeta {
        if let existing = noteMetas[noteID] {
            return existing
        }
        let meta = NoteMeta(noteID: noteID, folderID: folderID, orderIndex: nextNoteOrderIndex(folderID: folderID))
        noteMetas[noteID] = meta
        persist()
        return meta
    }

    /// Upserts a metadata row wholesale (used for seeding and migration).
    func insert(_ meta: NoteMeta) {
        noteMetas[meta.noteID] = meta
        persist()
    }

    /// Mutates the metadata of one note in place and persists the change.
    /// Returns `false` when no row exists for `noteID`.
    @discardableResult
    func update(_ noteID: String, _ mutate: (inout NoteMeta) -> Void) -> Bool {
        guard var meta = noteMetas[noteID] else { return false }
        mutate(&meta)
        noteMetas[noteID] = meta
        persist()
        return true
    }

    /// One-time migration for rows created before folder IDs were stored: rows
    /// whose folderID is still a folder NAME are re-homed to the real folder
    /// ID, and rows whose folderID is neither a known ID nor a known name are
    /// re-homed to the "All Notes" bucket so no user-visible folder names are
    /// retained. Idempotent and cheap after the first run.
    func migrateFolderNameKeys(_ folders: [NotesFolder]) {
        guard !folders.isEmpty else { return }
        // Duplicate folder names resolve to the first matching folder's ID.
        let idByName = Dictionary(folders.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let knownIDs = Set(folders.map(\.id))
        var rehomed: [(noteID: String, folderID: String)] = []
        for (noteID, meta) in noteMetas {
            let current = meta.folderID
            if current.isEmpty { continue }
            // A real folder ID always wins, even when it happens to equal a
            // folder name.
            if knownIDs.contains(current) { continue }
            if let id = idByName[current] {
                rehomed.append((noteID, id))
            } else {
                // Stale name for a deleted/nested folder -> All Notes bucket.
                rehomed.append((noteID, ""))
            }
        }
        guard !rehomed.isEmpty else { return }
        for entry in rehomed {
            noteMetas[entry.noteID]?.folderID = entry.folderID
        }
        persist()
    }

    func moveNote(noteID: String, folderID: String, to newIndex: Int) {
        var metas = orderedNoteMetas(folderID: folderID).filter { $0.noteID != noteID }
        guard metas.indices.contains(newIndex) else { return }
        let meta = noteMeta(createIfNeededFor: noteID, folderID: folderID)
        metas.insert(meta, at: newIndex)
        for (index, item) in metas.enumerated() {
            noteMetas[item.noteID]?.orderIndex = index
        }
        persist()
    }

    func orderedNoteMetas(folderID: String) -> [NoteMeta] {
        noteMetas.values.filter { $0.folderID == folderID }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func nextNoteOrderIndex(folderID: String) -> Int {
        orderedNoteMetas(folderID: folderID).count
    }
}
