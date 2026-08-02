import SwiftUI

/// Shared color helpers. Panels should prefer `Theme` colors.
enum AppColor {
    /// Known note/folder color palette.
    static let noteColors: [(name: String, hex: String)] = [
        ("Default", ""),
        ("Red", "E5484D"),
        ("Orange", "F76B15"),
        ("Yellow", "FFB224"),
        ("Green", "30A46C"),
        ("Blue", "0091FF"),
        ("Purple", "8E4EC6"),
        ("Pink", "E93D82"),
        ("Gray", "8D8D8F"),
    ]

    static func color(forHex hex: String) -> Color? {
        hex.isEmpty ? nil : ColorTokenParser.color(fromHex: hex)
    }
}
