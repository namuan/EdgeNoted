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
    /// flattened (no visible content lost). Never applied to rich notes.
    static func displayText(_ body: String) -> String {
        isPlainText(body) ? body : strippedForDisplay(body)
    }

    /// Strips HTML tags for display purposes only (never written back).
    static func strippedForDisplay(_ body: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: [.caseInsensitive]) else {
            return body
        }
        let textNS = body as NSString
        let range = NSRange(location: 0, length: textNS.length)
        let cleaned = regex.stringByReplacingMatches(in: body, range: range, withTemplate: "")
        return
            cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
