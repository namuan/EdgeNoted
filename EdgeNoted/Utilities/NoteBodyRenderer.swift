import Foundation

/// Renders a plain-text note body into segments: checklist lines, hex color
/// chips, and plain text. Also provides pure helpers used to toggle checklist
/// items inside the underlying body string.
enum NoteBodyRenderer {
    struct BodySegment: Equatable, Sendable {
        let text: String
        let isHexColor: Bool
    }

    static let checklistPrefixChecked = "- [x]"
    static let checklistPrefixUnchecked = "- [ ]"

    static func lines(of body: String) -> [String] {
        body.components(separatedBy: .newlines)
    }

    static func isChecklistLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(checklistPrefixUnchecked) || trimmed.hasPrefix(checklistPrefixChecked)
    }

    static func isChecked(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(checklistPrefixChecked)
    }

    static func checklistText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(checklistPrefixUnchecked) {
            return String(trimmed.dropFirst(checklistPrefixUnchecked.count))
                .trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix(checklistPrefixChecked) {
            return String(trimmed.dropFirst(checklistPrefixChecked.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// Returns the line with its checkbox toggled.
    static func toggled(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(checklistPrefixUnchecked) {
            return checklistPrefixChecked + String(trimmed.dropFirst(checklistPrefixUnchecked.count))
        }
        if trimmed.hasPrefix(checklistPrefixChecked) {
            return checklistPrefixUnchecked + String(trimmed.dropFirst(checklistPrefixChecked.count))
        }
        return line
    }

    /// Toggles the checklist item on `lineIndex` of `body`, preserving all
    /// other lines exactly. Returns nil when the target line is not a checklist.
    static func toggleChecklistItem(in body: String, at lineIndex: Int) -> String? {
        var lines = body.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex), isChecklistLine(lines[lineIndex]) else { return nil }
        lines[lineIndex] = toggled(lines[lineIndex])
        return lines.joined(separator: "\n")
    }

    /// Splits a line into segments, marking `#rrggbb`/`#rgb` tokens.
    static func segments(of line: String) -> [BodySegment] {
        let tokens = ColorTokenParser.tokens(in: line)
        guard !tokens.isEmpty else {
            return line.isEmpty ? [] : [BodySegment(text: line, isHexColor: false)]
        }
        var result: [BodySegment] = []
        var cursor = 0
        let textNS = line as NSString
        for token in tokens {
            if token.start > cursor {
                result.append(
                    BodySegment(
                        text: textNS.substring(with: NSRange(location: cursor, length: token.start - cursor)),
                        isHexColor: false
                    )
                )
            }
            result.append(
                BodySegment(
                    text: textNS.substring(with: NSRange(location: token.start, length: token.length)),
                    isHexColor: true
                )
            )
            cursor = token.start + token.length
        }
        if cursor < textNS.length {
            result.append(BodySegment(text: textNS.substring(from: cursor), isHexColor: false))
        }
        return result
    }
}
