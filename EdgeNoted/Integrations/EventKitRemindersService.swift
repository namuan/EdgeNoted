import Foundation
@preconcurrency import EventKit

/// Pure mapping helpers shared with tests. No EventKit types cross these
/// boundaries, so they stay unit-testable without touching the user's store.
enum EventKitReminderMapping {
    /// Converts EventKit due-date components into a Unix epoch, or nil when
    /// there is no due date. The components' own calendar/time zone win when
    /// present; otherwise the local calendar is used so date-only values land
    /// at that local day's midnight.
    static func dueEpoch(from components: DateComponents?) -> TimeInterval? {
        guard let components else { return nil }
        var calendar = components.calendar ?? Calendar.autoupdatingCurrent
        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }
        guard let date = calendar.date(from: components) else { return nil }
        return date.timeIntervalSince1970
    }

    /// Builds due-date components for saving from a Unix epoch, using the
    /// local calendar and time zone.
    static func dueComponents(from epoch: TimeInterval) -> DateComponents? {
        var components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: epoch)
        )
        components.calendar = Calendar.autoupdatingCurrent
        components.timeZone = .current
        return components
    }
}

/// RemindersService backed by EventKit. Owns one long-lived EKEventStore on
/// its own actor, requests full Reminders access on first use, and observes
/// store changes so AppState can refresh the panel.
actor EventKitRemindersService: RemindersService, RemindersChangeObserving {
    private var eventStore: EKEventStore?
    private var notificationToken: ObserverToken?

    /// Wraps the non-Sendable NotificationCenter token so the actor can own it.
    private final class ObserverToken: @unchecked Sendable {
        let value: NSObjectProtocol
        init(_ value: NSObjectProtocol) { self.value = value }
    }

    deinit {
        notificationToken.map { NotificationCenter.default.removeObserver($0.value) }
    }

    // MARK: - RemindersChangeObserving

    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        notificationToken.map { NotificationCenter.default.removeObserver($0.value) }
        notificationToken = nil
        guard let handler else { return }
        let store = store()
        let token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleStoreChanged() }
        }
        notificationToken = ObserverToken(token)
        self.changeHandler = handler
    }

    private var changeHandler: (@Sendable () -> Void)?

    private func handleStoreChanged() {
        // Previously fetched EKReminder objects are stale after a store change;
        // AppState refetches everything. The long-lived store itself stays
        // valid for new queries.
        guard let changeHandler else { return }
        changeHandler()
    }

    // MARK: - RemindersService

    func fetchLists() async throws -> [ReminderList] {
        try await ensureFullAccess()
        let calendars = store().calendars(for: .reminder)
        return calendars
            .map { ReminderList(id: $0.calendarIdentifier, name: $0.title) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchAllReminders() async throws -> [ReminderItem] {
        try await ensureFullAccess()
        let store = store()
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        return try await fetchReminders(matching: predicate)
    }

    func updateReminder(
        id: String,
        title: String?,
        isCompleted: Bool?,
        dueEpoch: TimeInterval?,
        priority: Int?,
        clearDueDate: Bool
    ) async throws {
        try await ensureFullAccess()
        let store = store()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersStoreError.notFound
        }
        if let title { reminder.title = title }
        if let isCompleted { reminder.isCompleted = isCompleted }
        if clearDueDate {
            reminder.dueDateComponents = nil
        } else if let dueEpoch {
            reminder.dueDateComponents = EventKitReminderMapping.dueComponents(from: dueEpoch)
        }
        if let priority { reminder.priority = priority }
        try store.save(reminder, commit: true)
    }

    func deleteReminder(id: String) async throws {
        try await ensureFullAccess()
        let store = store()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersStoreError.notFound
        }
        try store.remove(reminder, commit: true)
    }

    // MARK: - Mapping

    private static func map(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(
            id: reminder.calendarItemIdentifier,
            name: reminder.title ?? "",
            isCompleted: reminder.isCompleted,
            dueEpoch: EventKitReminderMapping.dueEpoch(from: reminder.dueDateComponents),
            priority: reminder.priority,
            listName: reminder.calendar?.title ?? ""
        )
    }

    // MARK: - Access

    private func ensureFullAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = await requestFullAccess()
            guard granted else {
                eventStore?.reset()
                eventStore = nil
                throw RemindersAccessError.accessDenied
            }
        case .writeOnly:
            throw RemindersAccessError.writeOnly
        case .denied:
            throw RemindersAccessError.accessDenied
        case .restricted:
            throw RemindersAccessError.accessRestricted
        @unknown default:
            throw RemindersAccessError.accessDenied
        }
    }

    private func requestFullAccess() async -> Bool {
        let store = store()
        return await withCheckedContinuation { continuation in
            store.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func store() -> EKEventStore {
        if let eventStore { return eventStore }
        let newStore = EKEventStore()
        eventStore = newStore
        return newStore
    }

    // MARK: - Fetching

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [ReminderItem] {
        let store = store()
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Map inside the completion so only Sendable values cross the
                // actor boundary.
                let items = (reminders ?? []).map(Self.map)
                continuation.resume(returning: items)
            }
        }
    }
}

/// A reminder that existed when the panel loaded but is gone by the time an
/// update or delete runs.
enum RemindersStoreError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "That reminder no longer exists in Reminders. The list will refresh."
    }
}
