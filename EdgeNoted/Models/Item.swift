import Foundation

struct Item: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var isComplete: Bool

    init(id: UUID = UUID(), name: String, isComplete: Bool = false) {
        self.id = id
        self.name = name
        self.isComplete = isComplete
    }

    enum ValidationError: Error {
        case emptyName
    }

    static func validate(name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyName
        }
    }
}
