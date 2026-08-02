import Foundation
import Testing

@testable import EdgeNoted

@Suite("Settings shortcut defaults")
struct SettingsStoreTests {
    @Test("New settings default to Control-Shift-N")
    func defaultShortcut() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "SettingsStoreTests-default-\(UUID().uuidString)")
        )
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.hotKeyCode == 45)
        #expect(settings.hotKeyControl)
        #expect(settings.hotKeyShift)
        #expect(!settings.hotKeyCommand)
        #expect(settings.hotKeyDescription == "⌃⇧N")
    }

    @Test("The old default migrates without changing custom shortcuts")
    func migratesOldDefaultOnly() throws {
        let oldDefaultSuite = "SettingsStoreTests-migrate-\(UUID().uuidString)"
        let oldDefaults = try #require(UserDefaults(suiteName: oldDefaultSuite))
        oldDefaults.set(45, forKey: "hotKeyCode")
        oldDefaults.set(false, forKey: "hotKeyControl")
        oldDefaults.set(false, forKey: "hotKeyOption")
        oldDefaults.set(true, forKey: "hotKeyShift")
        oldDefaults.set(true, forKey: "hotKeyCommand")
        let migrated = SettingsStore(defaults: oldDefaults)
        #expect(migrated.hotKeyDescription == "⌃⇧N")

        let customSuite = "SettingsStoreTests-custom-\(UUID().uuidString)"
        let customDefaults = try #require(UserDefaults(suiteName: customSuite))
        customDefaults.set(45, forKey: "hotKeyCode")
        customDefaults.set(false, forKey: "hotKeyControl")
        customDefaults.set(true, forKey: "hotKeyOption")
        customDefaults.set(true, forKey: "hotKeyShift")
        customDefaults.set(false, forKey: "hotKeyCommand")
        let custom = SettingsStore(defaults: customDefaults)
        #expect(custom.hotKeyDescription == "⌥⇧N")
    }
}
