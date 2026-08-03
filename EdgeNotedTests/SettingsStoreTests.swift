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

    @Test("Configured note defaults to nil and persists")
    func configuredNotePersistence() throws {
        let suite = "SettingsStoreTests-note-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.configuredNoteID == nil)
        #expect(settings.configuredNoteFolderName == nil)
        #expect(settings.configuredNoteName == nil)

        settings.configuredNoteID = "n42"
        settings.configuredNoteFolderName = "Work"
        settings.configuredNoteName = "Agenda"

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.configuredNoteID == "n42")
        #expect(reloaded.configuredNoteFolderName == "Work")
        #expect(reloaded.configuredNoteName == "Agenda")
    }
}
