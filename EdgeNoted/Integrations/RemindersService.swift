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
    var listName: String = ""

    var priorityLevel: ReminderPriority {
        ReminderPriority(rawValue: priority) ?? .none
    }

    /// Whether this incomplete reminder belongs in the overdue-and-today panel.
    func isDueTodayOrOverdue(referenceDate: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueEpoch else { return false }
        guard let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: referenceDate)
        ) else { return false }
        return Date(timeIntervalSince1970: dueEpoch) < startOfTomorrow
    }
}

// MARK: - Protocol

/// Bridge to Apple Reminders. Implementations must be Sendable.
protocol RemindersService: Sendable {
    func fetchLists() async throws -> [ReminderList]
    func fetchAllReminders() async throws -> [ReminderItem]
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

/// Optional capability for services that can observe external Reminders
/// changes. AppState subscribes when the concrete service supports it.
protocol RemindersChangeObserving: AnyObject {
    func setChangeHandler(_ handler: (@Sendable () -> Void)?) async
}

/// Errors surfaced by the EventKit-backed Reminders service. Kept separate
/// from ScriptError so the UI can distinguish automation failures (Notes) from
/// calendar-access failures (Reminders).
enum RemindersAccessError: LocalizedError, Equatable {
    case accessDenied
    case accessRestricted
    case writeOnly

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return
                "EdgeNoted is not allowed to access your Reminders. Grant access in System Settings > Privacy & Security > Reminders, then try again."
        case .accessRestricted:
            return "Reminders access is restricted on this Mac (parental controls or MDM)."
        case .writeOnly:
            return "Reminders access is limited to adding events. Full access is required to display reminders."
        }
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

    func fetchAllReminders() async throws -> [ReminderItem] {
        lists.flatMap { list in
            store[list.name]?.map {
                ReminderItem(
                    id: $0.key,
                    name: $0.value.name,
                    isCompleted: $0.value.isCompleted,
                    dueEpoch: $0.value.dueEpoch,
                    priority: $0.value.priority,
                    listName: list.name
                )
            } ?? []
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
