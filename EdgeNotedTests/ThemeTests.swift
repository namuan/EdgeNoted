import Foundation
import Testing

@testable import EdgeNoted

@Suite("Theme model")
struct ThemeTests {
    @Test("Built-in themes are valid and unique")
    func builtins() {
        #expect(!Theme.builtins.isEmpty)
        let ids = Set(Theme.builtins.map(\.id))
        #expect(ids.count == Theme.builtins.count)
        for theme in Theme.builtins {
            #expect(ColorTokenParser.components(fromHex: theme.accentHex) != nil)
            #expect(ColorTokenParser.components(fromHex: theme.backgroundHex) != nil)
            #expect(ColorTokenParser.components(fromHex: theme.textHex) != nil)
            #expect(ColorTokenParser.components(fromHex: theme.secondaryHex) != nil)
        }
    }

    @Test("Lookup falls back to the first built-in for unknown ids")
    func lookupFallback() {
        #expect(Theme.find(id: "does-not-exist", custom: []).id == Theme.builtins[0].id)
        #expect(Theme.find(id: "midnight", custom: []).name == "Midnight")
        #expect(
            Theme.find(
                id: "missing",
                custom: [
                    Theme(
                        id: "missing",
                        name: "Mine",
                        accentHex: "000000",
                        backgroundHex: "FFFFFF",
                        textHex: "111111",
                        secondaryHex: "999999",
                    )
                ]
            ).name == "Mine"
        )
    }

    @Test("Custom themes round-trip through Codable")
    func codableRoundTrip() throws {
        let custom = [
            Theme(
                id: "c1",
                name: "Mine",
                accentHex: "AA0000",
                backgroundHex: "FEFEFE",
                textHex: "101010",
                secondaryHex: "808080",
            )
        ]
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode([Theme].self, from: data)
        #expect(decoded == custom)
    }
}

@Suite("Reminder priority mapping")
struct ReminderPriorityTests {
    @Test("Uses the Apple Reminders convention")
    func mapping() {
        #expect(ReminderPriority.high.rawValue == 1)
        #expect(ReminderPriority.medium.rawValue == 5)
        #expect(ReminderPriority.low.rawValue == 9)
        #expect(ReminderPriority.none.rawValue == 0)
    }

    @Test("Unknown raw values fall back to none")
    func fallback() {
        let item = ReminderItem(id: "x", name: "n", isCompleted: false, dueEpoch: nil, priority: 7)
        #expect(item.priorityLevel == .none)
    }
}
