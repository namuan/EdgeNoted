import SwiftUI

/// Parses `#rrggbb` / `#rgb` hex color tokens from text.
enum ColorTokenParser {
    struct Token: Equatable, Sendable {
        let hex: String  // normalized 6-digit hex without '#'
        let start: Int  // UTF-16 offset
        let length: Int
    }

    struct RGBComponents: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let pattern = #"#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-fA-F])"#

    static func tokens(in text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let textNS = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: textNS.length))
        return matches.map { match in
            let raw = textNS.substring(with: match.range)
            let digits = raw.dropFirst()
            let normalized: String
            if digits.count == 3 {
                normalized = digits.map { "\($0)\($0)" }.joined()
            } else {
                normalized = String(digits)
            }
            return Token(hex: normalized.lowercased(), start: match.range.location, length: match.range.length)
        }
    }

    static func components(fromHex hex: String) -> RGBComponents? {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return RGBComponents(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    static func color(fromHex hex: String) -> Color? {
        guard let components = components(fromHex: hex) else { return nil }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// Converts a SwiftUI Color to a 6-digit hex string in the sRGB color
    /// space, used when editing custom themes.
    static func hexString(from color: Color) -> String? {
        let nsColor = NSColor(color).usingColorSpace(.sRGB)
        guard let nsColor else { return nil }
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
