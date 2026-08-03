import Foundation
import Testing

@testable import EdgeNoted

@Suite("EventKit reminder mapping")
struct EventKitRemindersServiceTests {
    @Test("Date-only components resolve to that local day's midnight")
    func dateOnlyComponents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.calendar = calendar
        components.timeZone = calendar.timeZone

        let epoch = try #require(EventKitReminderMapping.dueEpoch(from: components))
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))
        ).timeIntervalSince1970
        #expect(epoch == expected)
    }

    @Test("Timed components preserve the hour")
    func timedComponents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = 14
        components.minute = 30
        components.calendar = calendar
        components.timeZone = calendar.timeZone

        let epoch = try #require(EventKitReminderMapping.dueEpoch(from: components))
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 14, minute: 30))
        ).timeIntervalSince1970
        #expect(epoch == expected)
    }

    @Test("Nil components produce nil")
    func nilComponents() {
        #expect(EventKitReminderMapping.dueEpoch(from: nil) == nil)
    }

    @Test("Round trip epoch to components and back is stable")
    func roundTrip() throws {
        let epoch: TimeInterval = 1_784_649_600
        let components = try #require(EventKitReminderMapping.dueComponents(from: epoch))
        let mapped = try #require(EventKitReminderMapping.dueEpoch(from: components))
        #expect(abs(mapped - epoch) < 1)
    }

    @Test("Access errors carry actionable descriptions")
    func accessErrorDescriptions() {
        #expect(RemindersAccessError.accessDenied.errorDescription?.contains("Reminders") == true)
        #expect(RemindersAccessError.accessRestricted.errorDescription?.isEmpty == false)
        #expect(RemindersAccessError.writeOnly.errorDescription?.isEmpty == false)
    }

    @Test("Store errors carry actionable descriptions")
    func storeErrorDescriptions() {
        #expect(RemindersStoreError.notFound.errorDescription?.isEmpty == false)
        #expect(RemindersStoreError.listNotFound.errorDescription?.contains("list") == true)
        #expect(RemindersStoreError.listNotWritable.errorDescription?.isEmpty == false)
    }
}
