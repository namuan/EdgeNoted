import SwiftData

@MainActor
enum PersistenceController {
    static let container: ModelContainer = {
        let schema = Schema([])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer for EdgeNoted: \(error)")
        }
    }()
}
