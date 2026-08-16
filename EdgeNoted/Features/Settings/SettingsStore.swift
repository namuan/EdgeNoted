import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

/// User preferences, persisted in UserDefaults and observed by the UI.
@Observable
final class SettingsStore {
    private enum Keys {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyShortcutVersion = "hotKeyShortcutVersion"
        static let hotKeyControl = "hotKeyControl"
        static let hotKeyOption = "hotKeyOption"
        static let hotKeyShift = "hotKeyShift"
        static let hotKeyCommand = "hotKeyCommand"
        static let hotSideEnabled = "hotSideEnabled"
        static let hotSideEdge = "hotSideEdge"
        static let hotSideThreshold = "hotSideThreshold"
        static let hotSideArmDelay = "hotSideArmDelay"
        static let autoHideDelay = "autoHideDelay"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let panelMargin = "panelMargin"
        static let themeName = "themeName"
        static let customThemes = "customThemes"
        static let launchAtLogin = "launchAtLogin"
        static let configuredNoteID = "configuredNoteID"
        static let configuredNoteFolderName = "configuredNoteFolderName"
        static let configuredNoteName = "configuredNoteName"
        static let reminderHorizon = "reminderHorizon"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Global hotkey

    var hotKeyCode: Int {
        didSet { defaults.set(hotKeyCode, forKey: Keys.hotKeyCode) }
    }

    var hotKeyControl: Bool {
        didSet { defaults.set(hotKeyControl, forKey: Keys.hotKeyControl) }
    }

    var hotKeyOption: Bool {
        didSet { defaults.set(hotKeyOption, forKey: Keys.hotKeyOption) }
    }

    var hotKeyShift: Bool {
        didSet { defaults.set(hotKeyShift, forKey: Keys.hotKeyShift) }
    }

    var hotKeyCommand: Bool {
        didSet { defaults.set(hotKeyCommand, forKey: Keys.hotKeyCommand) }
    }

    // MARK: Hot Side

    var hotSideEnabled: Bool {
        didSet { defaults.set(hotSideEnabled, forKey: Keys.hotSideEnabled) }
    }

    var hotSideEdge: ScreenEdge {
        didSet { defaults.set(hotSideEdge.rawValue, forKey: Keys.hotSideEdge) }
    }

    var hotSideThreshold: Double {
        didSet { defaults.set(hotSideThreshold, forKey: Keys.hotSideThreshold) }
    }

    var hotSideArmDelay: Double {
        didSet { defaults.set(hotSideArmDelay, forKey: Keys.hotSideArmDelay) }
    }

    var autoHideDelay: Double {
        didSet { defaults.set(autoHideDelay, forKey: Keys.autoHideDelay) }
    }

    // MARK: Panel

    var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) }
    }

    var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Keys.panelHeight) }
    }

    var panelMargin: Double {
        didSet { defaults.set(panelMargin, forKey: Keys.panelMargin) }
    }

    // MARK: Appearance

    var themeName: String {
        didSet { defaults.set(themeName, forKey: Keys.themeName) }
    }

    var customThemesData: Data? {
        didSet { defaults.set(customThemesData, forKey: Keys.customThemes) }
    }

    // MARK: Misc

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    // MARK: Displayed note

    /// The single Apple Notes note the panel displays. Selected in Settings.
    var configuredNoteID: String? {
        didSet { defaults.set(configuredNoteID, forKey: Keys.configuredNoteID) }
    }

    /// Name of the folder the configured note lives in; used to select that
    /// folder when the configured note is reloaded.
    var configuredNoteFolderName: String? {
        didSet { defaults.set(configuredNoteFolderName, forKey: Keys.configuredNoteFolderName) }
    }

    /// Display name of the configured note, stored so Settings can show a
    /// label even before the note list has been loaded.
    var configuredNoteName: String? {
        didSet { defaults.set(configuredNoteName, forKey: Keys.configuredNoteName) }
    }

    // MARK: Reminders

    /// How far ahead the Reminders panel looks. Defaults to overdue + today.
    var reminderHorizon: ReminderHorizon {
        didSet { defaults.set(reminderHorizon.rawValue, forKey: Keys.reminderHorizon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedKeyCode = defaults.object(forKey: Keys.hotKeyCode) as? Int ?? 45  // kVK_ANSI_N
        let storedControl = defaults.object(forKey: Keys.hotKeyControl) as? Bool ?? true
        let storedOption = defaults.object(forKey: Keys.hotKeyOption) as? Bool ?? false
        let storedShift = defaults.object(forKey: Keys.hotKeyShift) as? Bool ?? true
        let storedCommand = defaults.object(forKey: Keys.hotKeyCommand) as? Bool ?? false
        let storedShortcutVersion = defaults.integer(forKey: Keys.hotKeyShortcutVersion)

        // Migrate the original default (⌘⇧N) to the product shortcut (⌃⇧N)
        // without overwriting a shortcut the user has explicitly customized.
        let isOriginalDefault =
            storedKeyCode == 45
            && !storedControl
            && !storedOption
            && storedShift
            && storedCommand
        let shouldMigrateShortcut = storedShortcutVersion < 2 && isOriginalDefault

        hotKeyCode = storedKeyCode
        hotKeyControl = shouldMigrateShortcut ? true : storedControl
        hotKeyOption = storedOption
        hotKeyShift = storedShift
        hotKeyCommand = shouldMigrateShortcut ? false : storedCommand
        defaults.set(2, forKey: Keys.hotKeyShortcutVersion)
        hotSideEnabled = defaults.object(forKey: Keys.hotSideEnabled) as? Bool ?? true
        hotSideEdge = ScreenEdge(rawValue: defaults.string(forKey: Keys.hotSideEdge) ?? "") ?? .right
        hotSideThreshold = defaults.object(forKey: Keys.hotSideThreshold) as? Double ?? 8
        hotSideArmDelay = defaults.object(forKey: Keys.hotSideArmDelay) as? Double ?? 0.12
        autoHideDelay = defaults.object(forKey: Keys.autoHideDelay) as? Double ?? 2.0
        panelWidth = defaults.object(forKey: Keys.panelWidth) as? Double ?? 460
        panelHeight = defaults.object(forKey: Keys.panelHeight) as? Double ?? 600
        panelMargin = defaults.object(forKey: Keys.panelMargin) as? Double ?? 0
        themeName = defaults.string(forKey: Keys.themeName) ?? Theme.builtins[0].id
        customThemesData = defaults.data(forKey: Keys.customThemes)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        configuredNoteID = defaults.string(forKey: Keys.configuredNoteID)
        configuredNoteFolderName = defaults.string(forKey: Keys.configuredNoteFolderName)
        configuredNoteName = defaults.string(forKey: Keys.configuredNoteName)
        reminderHorizon = ReminderHorizon(rawValue: defaults.string(forKey: Keys.reminderHorizon) ?? "") ?? .today
    }

    // MARK: Derived

    var panelSize: CGSize {
        CGSize(width: panelWidth, height: panelHeight)
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if hotKeyControl { flags |= UInt32(controlKey) }
        if hotKeyOption { flags |= UInt32(optionKey) }
        if hotKeyShift { flags |= UInt32(shiftKey) }
        if hotKeyCommand { flags |= UInt32(cmdKey) }
        return flags
    }

    var hotKeyDescription: String {
        var parts: [String] = []
        if hotKeyControl { parts.append("⌃") }
        if hotKeyOption { parts.append("⌥") }
        if hotKeyShift { parts.append("⇧") }
        if hotKeyCommand { parts.append("⌘") }
        parts.append(Self.keyName(for: hotKeyCode))
        return parts.joined()
    }

    var customThemes: [Theme] {
        get {
            guard let customThemesData,
                let themes = try? JSONDecoder().decode([Theme].self, from: customThemesData)
            else {
                return []
            }
            return themes
        }
        set {
            customThemesData = try? JSONEncoder().encode(newValue)
        }
    }

    func activeTheme() -> Theme {
        Theme.find(id: themeName, custom: customThemes)
    }

    // MARK: Custom themes

    @discardableResult
    func addCustomTheme() -> Theme {
        let theme = Theme(
            id: UUID().uuidString,
            name: "Custom \(customThemes.count + 1)",
            accentHex: "0A84FF",
            backgroundHex: "F5F5F4",
            textHex: "1D1D1F",
            secondaryHex: "6E6E73",
        )
        customThemes.append(theme)
        themeName = theme.id
        return theme
    }

    func duplicateCustomTheme(id: String) {
        guard let source = customThemes.first(where: { $0.id == id }) else { return }
        let copy = Theme(
            id: UUID().uuidString,
            name: "\(source.name) Copy",
            accentHex: source.accentHex,
            backgroundHex: source.backgroundHex,
            textHex: source.textHex,
            secondaryHex: source.secondaryHex,
        )
        customThemes.append(copy)
    }

    func deleteCustomTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        if themeName == id {
            themeName = Theme.builtins[0].id
        }
    }

    /// Updates one color field of a custom theme from a SwiftUI Color picker.
    func updateCustomTheme(id: String, hexField: KeyPath<Theme, String>, to color: Color) {
        var themes = customThemes
        guard let index = themes.firstIndex(where: { $0.id == id }),
            let hex = ColorTokenParser.hexString(from: color)
        else {
            return
        }
        let current = themes[index]
        let updated: Theme
        switch hexField {
        case \.accentHex:
            updated = Theme(
                id: current.id,
                name: current.name,
                accentHex: hex,
                backgroundHex: current.backgroundHex,
                textHex: current.textHex,
                secondaryHex: current.secondaryHex,
            )
        case \.backgroundHex:
            updated = Theme(
                id: current.id,
                name: current.name,
                accentHex: current.accentHex,
                backgroundHex: hex,
                textHex: current.textHex,
                secondaryHex: current.secondaryHex,
            )
        case \.textHex:
            updated = Theme(
                id: current.id,
                name: current.name,
                accentHex: current.accentHex,
                backgroundHex: current.backgroundHex,
                textHex: hex,
                secondaryHex: current.secondaryHex,
            )
        default:
            updated = Theme(
                id: current.id,
                name: current.name,
                accentHex: current.accentHex,
                backgroundHex: current.backgroundHex,
                textHex: current.textHex,
                secondaryHex: hex,
            )
        }
        themes[index] = updated
        customThemes = themes
    }

    /// Best-effort human name for a Carbon virtual key code.
    private static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "O"
        case 32: "U"
        case 33: "["
        case 34: "I"
        case 35: "P"
        case 36: "Return"
        case 37: "L"
        case 38: "J"
        case 39: "'"
        case 40: "K"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "N"
        case 46: "M"
        case 47: "."
        case 48: "Tab"
        case 49: "Space"
        case 51: "Delete"
        case 53: "Esc"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "Key \(keyCode)"
        }
    }
}
