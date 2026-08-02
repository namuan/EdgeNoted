import SwiftUI

/// A named color theme. Custom themes are persisted in SettingsStore as JSON.
struct Theme: Equatable, Identifiable, Sendable, Codable {
    let id: String
    let name: String
    let accentHex: String
    let backgroundHex: String
    let textHex: String
    let secondaryHex: String

    var accentColor: Color {
        ColorTokenParser.color(fromHex: accentHex) ?? .accentColor
    }

    var backgroundColor: Color {
        ColorTokenParser.color(fromHex: backgroundHex) ?? Color(nsColor: .windowBackgroundColor)
    }

    var textColor: Color {
        ColorTokenParser.color(fromHex: textHex) ?? .primary
    }

    var secondaryColor: Color {
        ColorTokenParser.color(fromHex: secondaryHex) ?? .secondary
    }

    static let builtins: [Theme] = [
        Theme(
            id: "daylight",
            name: "Daylight",
            accentHex: "0A84FF",
            backgroundHex: "F5F5F4",
            textHex: "1D1D1F",
            secondaryHex: "6E6E73"
        ),
        Theme(
            id: "midnight",
            name: "Midnight",
            accentHex: "64D2FF",
            backgroundHex: "1C1C1E",
            textHex: "F2F2F7",
            secondaryHex: "98989F"
        ),
        Theme(
            id: "paper",
            name: "Paper",
            accentHex: "B4652F",
            backgroundHex: "FBF6E9",
            textHex: "2B2118",
            secondaryHex: "8A7B6B"
        ),
        Theme(
            id: "mint",
            name: "Mint",
            accentHex: "1B7F5A",
            backgroundHex: "EAF6F0",
            textHex: "10392B",
            secondaryHex: "5E8A76"
        ),
    ]

    static func find(id: String, custom: [Theme]) -> Theme {
        if let theme = custom.first(where: { $0.id == id }) {
            return theme
        }
        return builtins.first(where: { $0.id == id }) ?? builtins[0]
    }
}
