import SwiftData

/// Owns the SwiftData container for local-only EdgeNoted metadata.
@MainActor
enum PersistenceController {
    static let container: ModelContainer = {
        do {
            let container = try makeContainer(isStoredInMemoryOnly: false)
            Log.info("SwiftData store opened", category: .persistence)
            return container
        } catch {
            Log.error("Failed to create ModelContainer", category: .persistence)
            fatalError("Failed to create ModelContainer for EdgeNoted: \(error)")
        }
    }()

    /// In-memory container for unit tests.
    static func inMemoryContainer() throws -> ModelContainer {
        try makeContainer(isStoredInMemoryOnly: true)
    }

    private static func makeContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema([
            NoteMeta.self,
            FolderMeta.self,
            Snippet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
