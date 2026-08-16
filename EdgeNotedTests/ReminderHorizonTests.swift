import Foundation
import Testing

@testable import EdgeNoted

/// Filtering rules behind the Reminders panel's horizon control.
@Suite("Reminder horizon filtering")
struct ReminderHorizonTests {
    /// A fixed noon reference so tests are independent of the wall clock.
    private struct Fixture {
        let calendar: Calendar
        let reference: Date
        let startOfToday: Date
    }

    private static func fixture() throws -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))
        )
        return Fixture(calendar: calendar, reference: reference, startOfToday: calendar.startOfDay(for: reference))
    }

    private static func item(
        _ id: String,
        completed: Bool = false,
        dueEpoch: TimeInterval?
    ) -> ReminderItem {
        ReminderItem(id: id, name: id, isCompleted: completed, dueEpoch: dueEpoch, priority: 0)
    }

    @Test("Days map to the expected window sizes")
    func dayWindows() {
        #expect(ReminderHorizon.today.days == 1)
        #expect(ReminderHorizon.twoDays.days == 2)
        #expect(ReminderHorizon.threeDays.days == 3)
        #expect(ReminderHorizon.sevenDays.days == 7)
        #expect(ReminderHorizon.thirtyDays.days == 30)
        #expect(ReminderHorizon.all.days == nil)
    }

    @Test("Today horizon shows overdue and today, hides tomorrow and beyond")
    func todayHorizon() throws {
        let fixture = try Self.fixture()
        let overdue = Self.item("overdue", dueEpoch: fixture.startOfToday.addingTimeInterval(-86_400).timeIntervalSince1970)
        let today = Self.item("today", dueEpoch: fixture.startOfToday.timeIntervalSince1970)
        let tomorrow = Self.item("tomorrow", dueEpoch: fixture.startOfToday.addingTimeInterval(86_400).timeIntervalSince1970)

        #expect(overdue.isVisible(in: .today, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(today.isVisible(in: .today, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!tomorrow.isVisible(in: .today, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("Two-day horizon adds tomorrow")
    func twoDayHorizon() throws {
        let fixture = try Self.fixture()
        let tomorrow = Self.item("tomorrow", dueEpoch: fixture.startOfToday.addingTimeInterval(86_400).timeIntervalSince1970)
        let dayAfter = Self.item("dayAfter", dueEpoch: fixture.startOfToday.addingTimeInterval(2 * 86_400).timeIntervalSince1970)

        #expect(tomorrow.isVisible(in: .twoDays, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!dayAfter.isVisible(in: .twoDays, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("Three-day horizon adds the day after tomorrow")
    func threeDayHorizon() throws {
        let fixture = try Self.fixture()
        let dayAfter = Self.item("dayAfter", dueEpoch: fixture.startOfToday.addingTimeInterval(2 * 86_400).timeIntervalSince1970)
        let thirdDay = Self.item("thirdDay", dueEpoch: fixture.startOfToday.addingTimeInterval(3 * 86_400).timeIntervalSince1970)

        #expect(dayAfter.isVisible(in: .threeDays, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!thirdDay.isVisible(in: .threeDays, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("Seven and thirty day horizons scale to their windows")
    func wideHorizons() throws {
        let fixture = try Self.fixture()
        let inAWeek = Self.item("inAWeek", dueEpoch: fixture.startOfToday.addingTimeInterval(7 * 86_400 - 1).timeIntervalSince1970)
        let pastAWeek = Self.item("pastAWeek", dueEpoch: fixture.startOfToday.addingTimeInterval(7 * 86_400).timeIntervalSince1970)
        let inAMonth = Self.item("inAMonth", dueEpoch: fixture.startOfToday.addingTimeInterval(30 * 86_400 - 1).timeIntervalSince1970)
        let pastAMonth = Self.item("pastAMonth", dueEpoch: fixture.startOfToday.addingTimeInterval(30 * 86_400).timeIntervalSince1970)

        #expect(inAWeek.isVisible(in: .sevenDays, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!pastAWeek.isVisible(in: .sevenDays, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(inAMonth.isVisible(in: .thirtyDays, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!pastAMonth.isVisible(in: .thirtyDays, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("All horizon shows every incomplete reminder, including unscheduled")
    func allHorizon() throws {
        let fixture = try Self.fixture()
        let unscheduled = Self.item("unscheduled", dueEpoch: nil)
        let farFuture = Self.item("farFuture", dueEpoch: fixture.startOfToday.addingTimeInterval(365 * 86_400).timeIntervalSince1970)
        let completed = Self.item("completed", completed: true, dueEpoch: nil)

        #expect(unscheduled.isVisible(in: .all, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(farFuture.isVisible(in: .all, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(!completed.isVisible(in: .all, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("Completed reminders are hidden in every horizon")
    func completedNeverVisible() throws {
        let fixture = try Self.fixture()
        let done = Self.item("done", completed: true, dueEpoch: fixture.startOfToday.timeIntervalSince1970)

        for horizon in ReminderHorizon.allCases {
            #expect(!done.isVisible(in: horizon, referenceDate: fixture.reference, calendar: fixture.calendar))
        }
    }

    @Test("Unscheduled reminders are hidden outside the all horizon")
    func unscheduledHiddenUnlessAll() throws {
        let fixture = try Self.fixture()
        let unscheduled = Self.item("unscheduled", dueEpoch: nil)

        for horizon in ReminderHorizon.allCases where horizon != .all {
            #expect(!unscheduled.isVisible(in: horizon, referenceDate: fixture.reference, calendar: fixture.calendar))
        }
    }

    @Test("Due exactly at the horizon cutoff is excluded")
    func cutoffExclusive() throws {
        let fixture = try Self.fixture()
        let atCutoff = Self.item("atCutoff", dueEpoch: fixture.startOfToday.addingTimeInterval(86_400).timeIntervalSince1970)
        let justInside = Self.item("justInside", dueEpoch: fixture.startOfToday.addingTimeInterval(86_400 - 1).timeIntervalSince1970)

        #expect(!atCutoff.isVisible(in: .today, referenceDate: fixture.reference, calendar: fixture.calendar))
        #expect(justInside.isVisible(in: .today, referenceDate: fixture.reference, calendar: fixture.calendar))
    }

    @Test("Horizon labels are distinct and non-empty")
    func labels() {
        for horizon in ReminderHorizon.allCases {
            #expect(!horizon.shortTitle.isEmpty)
            #expect(!horizon.title.isEmpty)
            #expect(!horizon.subtitle.isEmpty)
            #expect(!horizon.emptyStateTitle.isEmpty)
            #expect(!horizon.emptyStateDescription.isEmpty)
        }
        let titles = Set(ReminderHorizon.allCases.map(\.title))
        #expect(titles.count == ReminderHorizon.allCases.count)
    }
}
