import Foundation

// MARK: - Data types

struct ReminderList: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Reminders priority convention: 1 = high, 5 = medium, 9 = low, 0 = none.
enum ReminderPriority: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

struct ReminderItem: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var isCompleted: Bool
    var dueEpoch: TimeInterval?
    var priority: Int

    var priorityLevel: ReminderPriority {
        ReminderPriority(rawValue: priority) ?? .none
    }
}

// MARK: - Protocol

/// Bridge to Apple Reminders. Implementations must be Sendable.
protocol RemindersService: Sendable {
    func fetchLists() async throws -> [ReminderList]
    func fetchReminders(listName: String) async throws -> [ReminderItem]
    func createReminder(title: String, listName: String) async throws -> ReminderItem
    func updateReminder(
        id: String,
        title: String?,
        isCompleted: Bool?,
        dueEpoch: TimeInterval?,
        priority: Int?,
        clearDueDate: Bool
    ) async throws
    func deleteReminder(id: String) async throws
}

// MARK: - AppleScript implementation

/// RemindersService backed by the Apple Reminders AppleScript dictionary.
final class AppleScriptRemindersService: RemindersService, @unchecked Sendable {
    private let executor: AppleScriptExecutor

    init(executor: AppleScriptExecutor = .shared) {
        self.executor = executor
    }

    func fetchLists() async throws -> [ReminderList] {
        try await logged("fetchLists") {
            let output = try await executor.run(command: "lists")
            let entries = try decode([ListEntry].self, from: output)
            return entries.map { ReminderList(id: $0.idStr, name: $0.nameStr) }
        }
    }

    func fetchReminders(listName: String) async throws -> [ReminderItem] {
        try await logged("fetchReminders", reminderID: Log.digest(listName)) {
            let output = try await executor.run(command: "reminders", arguments: [listName])
            let entries = try decode([ReminderEntry].self, from: output)
            return entries.map { entry in
                ReminderItem(
                    id: entry.idStr,
                    name: entry.nameStr,
                    isCompleted: entry.doneStr == "true",
                    dueEpoch: Double(entry.dueStr).flatMap { $0 > 0 ? $0 : nil },
                    priority: Int(entry.priStr) ?? 0
                )
            }
        }
    }

    func createReminder(title: String, listName: String) async throws -> ReminderItem {
        try await logged("createReminder", reminderID: Log.digest(listName)) {
            let output = try await executor.run(command: "reminder-create", arguments: [listName, title])
            let entry = try decode(ReminderEntry.self, from: output)
            if let error = entry.errorStr {
                throw ScriptError.executionFailed(error)
            }
            return ReminderItem(id: entry.idStr, name: entry.nameStr, isCompleted: false, dueEpoch: nil, priority: 0)
        }
    }

    func updateReminder(
        id: String,
        title: String?,
        isCompleted: Bool?,
        dueEpoch: TimeInterval?,
        priority: Int?,
        clearDueDate: Bool = false
    ) async throws {
        try await logged("updateReminder", reminderID: id) {
            let titleArg = title ?? ""
            let doneArg = isCompleted.map { $0 ? "1" : "0" } ?? ""
            let dueArg: String
            if clearDueDate {
                dueArg = "clear"
            } else {
                dueArg = dueEpoch.map { String(Int($0)) } ?? ""
            }
            let priorityArg = priority.map { String($0) } ?? ""
            let output = try await executor.run(
                command: "reminder-update",
                arguments: [id, titleArg, doneArg, dueArg, priorityArg]
            )
            guard output.hasPrefix("OK") else {
                throw ScriptError.executionFailed(output)
            }
        }
    }

    func deleteReminder(id: String) async throws {
        try await logged("deleteReminder", reminderID: id) {
            let output = try await executor.run(command: "reminder-delete", arguments: [id])
            guard output.hasPrefix("OK") else {
                throw ScriptError.executionFailed(output)
            }
        }
    }

    private func logged<T>(_ operation: String, reminderID: String? = nil, _ body: () async throws -> T) async throws
        -> T
    {
        let startedAt = Date()
        do {
            let result = try await body()
            Log.info(
                "Reminders \(operation) ok",
                category: .reminders,
                metadata: [
                    "reminderId": reminderID ?? "-",
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
            return result
        } catch {
            Log.error(
                "Reminders \(operation) failed",
                category: .reminders,
                metadata: [
                    "reminderId": reminderID ?? "-",
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
            throw error
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw ScriptError.malformedOutput(output)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ScriptError.malformedOutput(output)
        }
    }

    private struct ListEntry: Decodable {
        let idStr: String
        let nameStr: String
    }

    private struct ReminderEntry: Decodable {
        let idStr: String
        let nameStr: String
        let doneStr: String
        let dueStr: String
        let priStr: String
        let errorStr: String?
    }
}

// MARK: - Fake implementation (tests / UI tests)

/// In-memory RemindersService used by unit tests and UI tests.
actor FakeRemindersService: RemindersService {
    private struct StoredReminder: Sendable {
        var name: String
        var isCompleted: Bool
        var dueEpoch: TimeInterval?
        var priority: Int
    }

    private var lists: [ReminderList]
    private var store: [String: [String: StoredReminder]]

    init(
        lists: [ReminderList] = [
            ReminderList(id: "l-work", name: "Work"),
            ReminderList(id: "l-home", name: "Home"),
        ]
    ) {
        self.lists = lists
        self.store = Dictionary(uniqueKeysWithValues: lists.map { ($0.name, [:]) })
    }

    func seed(name: String, listName: String, isCompleted: Bool = false) {
        let id = "fake-reminder-\(abs(name.hashValue))"
        store[listName]?[id] = StoredReminder(name: name, isCompleted: isCompleted, dueEpoch: nil, priority: 0)
    }

    func fetchLists() async throws -> [ReminderList] {
        lists
    }

    func fetchReminders(listName: String) async throws -> [ReminderItem] {
        store[listName]?
            .map {
                ReminderItem(
                    id: $0.key,
                    name: $0.value.name,
                    isCompleted: $0.value.isCompleted,
                    dueEpoch: $0.value.dueEpoch,
                    priority: $0.value.priority
                )
            }
            ?? []
    }

    func createReminder(title: String, listName: String) async throws -> ReminderItem {
        let id = "fake-reminder-\(abs(title.hashValue))"
        store[listName]?[id] = StoredReminder(name: title, isCompleted: false, dueEpoch: nil, priority: 0)
        return ReminderItem(id: id, name: title, isCompleted: false, dueEpoch: nil, priority: 0)
    }

    func updateReminder(
        id: String,
        title: String?,
        isCompleted: Bool?,
        dueEpoch: TimeInterval?,
        priority: Int?,
        clearDueDate: Bool = false
    ) async throws {
        guard let listName = store.keys.first(where: { store[$0]?[id] != nil }),
            var reminder = store[listName]?[id]
        else {
            throw ScriptError.executionFailed("Reminder not found: \(id)")
        }
        if let title { reminder.name = title }
        if let isCompleted { reminder.isCompleted = isCompleted }
        if clearDueDate {
            reminder.dueEpoch = nil
        } else if let dueEpoch {
            reminder.dueEpoch = dueEpoch
        }
        if let priority { reminder.priority = priority }
        store[listName]?[id] = reminder
    }

    func deleteReminder(id: String) async throws {
        guard let listName = store.keys.first(where: { store[$0]?[id] != nil }) else { return }
        store[listName]?.removeValue(forKey: id)
    }
}
