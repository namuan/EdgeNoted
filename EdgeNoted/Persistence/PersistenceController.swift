import Foundation

/// Owns the local metadata store for EdgeNoted's app-wide state. The store
/// persists to a JSON file in Application Support (see `defaultFileURL`), so
/// the app has no dependency on the SwiftData framework or its Xcode-only
/// macro plugins.
@MainActor
enum PersistenceController {
    /// The app-wide store, backed by the on-disk JSON file.
    static let shared = MetaStore(fileURL: defaultFileURL)

    /// A purely in-memory store for unit tests.
    static func makeInMemoryStore() -> MetaStore {
        MetaStore(fileURL: nil)
    }

    static var defaultFileURL: URL {
        let directory =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return directory.appendingPathComponent("EdgeNoted/metadata.json")
    }
}
