import Foundation

/// Decides whether a note body can be edited as plain text.
///
/// Apple Notes stores every body as HTML. Many notes are only wrapped in
/// structural tags (`<div>`, `<p>`, `<br>`) with no real formatting; those are
/// safe to flatten to plain text. Notes that contain actual rich content
/// (headings, lists, bold, images, links, tables) are shown read-only with an
/// explicit opt-in to convert, because rewriting them as text would destroy
/// the formatting.
enum NoteBodyClassifier {
    private static let emptyLineToken = "\u{E000}"
    private static let richTagPattern =
        #"<\s*(?:h[1-6]|ul|ol|li|b|strong|i|em|u|img|a|span|table|pre|code|blockquote)[\s>]"#

    /// True when the body contains no HTML tags at all.
    static func isPlainText(_ body: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else {
            return true
        }
        let textNS = body as NSString
        return regex.firstMatch(in: body, range: NSRange(location: 0, length: textNS.length)) == nil
    }

    /// True when the body's tags are only structural (`<div>`, `<p>`, `<br>`),
    /// so flattening it to plain text loses no visible content.
    static func isStructurallyPlain(_ body: String) -> Bool {
        if isPlainText(body) { return true }
        guard let regex = try? NSRegularExpression(pattern: richTagPattern, options: [.caseInsensitive]) else {
            return true
        }
        let textNS = body as NSString
        return regex.firstMatch(in: body, range: NSRange(location: 0, length: textNS.length)) == nil
    }

    /// The editing contract used by the note editor: structurally plain notes
    /// are editable; notes with rich content are read-only.
    static func isEditableAsPlainText(_ body: String) -> Bool {
        isStructurallyPlain(body)
    }

    /// The text shown in the editor: plain text as-is, and structural HTML
    /// converted to plain text while preserving its line structure. Never
    /// applied to rich notes.
    static func displayText(_ body: String) -> String {
        isPlainText(body) ? body : strippedForDisplay(body)
    }

    /// Converts the editor's plain text into structural HTML that Apple Notes
    /// preserves when assigned through AppleScript.
    static func htmlForWriting(_ body: String) -> String {
        let normalizedBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizedBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.isEmpty ? "<div><br></div>" : "<div>\(escapedForHTML(String(line)))</div>"
            }
            .joined()
    }

    /// Strips HTML tags for display purposes only (never written back).
    static func strippedForDisplay(_ body: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: [.caseInsensitive]) else {
            return body
        }
        let textWithEmptyLineTokens = body.replacingOccurrences(
            of: #"<\s*(?:div|p)\s*>\s*<\s*br\s*/?\s*>\s*</\s*(?:div|p)\s*>(?:\r\n|\r|\n)?"#,
            with: emptyLineToken,
            options: [.regularExpression, .caseInsensitive]
        )
        let textWithLineBreaks = textWithEmptyLineTokens
            .replacingOccurrences(
                of: #"<\s*br\s*/?\s*>"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"</\s*(?:div|p)\s*>(?:\r\n|\r|\n)?"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        let cleaned = regex.stringByReplacingMatches(
            in: textWithLineBreaks,
            range: NSRange(location: 0, length: (textWithLineBreaks as NSString).length),
            withTemplate: ""
        )
        var displayText = cleaned
        if displayText.hasSuffix(emptyLineToken) {
            displayText.removeLast(emptyLineToken.count)
        } else if displayText.hasSuffix("\n") {
            displayText.removeLast()
        }
        return
            displayText
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt", with: "<")
            .replacingOccurrences(of: "&gt", with: ">")
            .replacingOccurrences(of: "&quot", with: "\"")
            .replacingOccurrences(of: "&#39", with: "'")
            .replacingOccurrences(of: "&nbsp", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&amp", with: "&")
            .replacingOccurrences(of: emptyLineToken, with: "\n")
    }

    private static func escapedForHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
