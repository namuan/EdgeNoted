import Testing

@testable import EdgeNoted

@Suite("Note body rendering helpers")
struct NoteBodyRendererTests {
    @Test("Detects checklist lines")
    func detectsChecklists() {
        #expect(NoteBodyRenderer.isChecklistLine("- [ ] todo"))
        #expect(NoteBodyRenderer.isChecklistLine("  - [x] done"))
        #expect(!NoteBodyRenderer.isChecklistLine("plain line"))
        #expect(!NoteBodyRenderer.isChecklistLine("- [nope]"))
    }

    @Test("Checklist state and text extraction")
    func checklistState() {
        #expect(NoteBodyRenderer.isChecked("- [x] done"))
        #expect(!NoteBodyRenderer.isChecked("- [ ] todo"))
        #expect(NoteBodyRenderer.checklistText("- [ ] Buy milk") == "Buy milk")
    }

    @Test("Toggling preserves the rest of the body")
    func togglingPreservesBody() throws {
        let body = "Title\n- [ ] one\nmiddle\n- [x] two\n"
        let toggled = try #require(NoteBodyRenderer.toggleChecklistItem(in: body, at: 1))
        #expect(toggled == "Title\n- [x] one\nmiddle\n- [x] two\n")
        let reverted = try #require(NoteBodyRenderer.toggleChecklistItem(in: toggled, at: 1))
        #expect(reverted == body)
    }

    @Test("Toggling a non-checklist line returns nil")
    func togglingInvalidLine() {
        let body = "no checklist here"
        #expect(NoteBodyRenderer.toggleChecklistItem(in: body, at: 0) == nil)
        #expect(NoteBodyRenderer.toggleChecklistItem(in: body, at: 5) == nil)
    }

    @Test("Splits lines into segments and marks hex tokens")
    func segments() {
        let segments = NoteBodyRenderer.segments(of: "accent #0A84FF done")
        #expect(segments.count == 3)
        #expect(segments[0] == NoteBodyRenderer.BodySegment(text: "accent ", isHexColor: false))
        #expect(segments[1] == NoteBodyRenderer.BodySegment(text: "#0A84FF", isHexColor: true))
        #expect(segments[2] == NoteBodyRenderer.BodySegment(text: " done", isHexColor: false))
    }

    @Test("Empty lines produce no segments")
    func emptyLineSegments() {
        #expect(NoteBodyRenderer.segments(of: "").isEmpty)
    }
}

@Suite("Note body classifier")
struct NoteBodyClassifierTests {
    @Test("Plain text has no markup")
    func plainText() {
        #expect(NoteBodyClassifier.isPlainText("Just some text\nwith lines"))
        #expect(NoteBodyClassifier.isPlainText("- [ ] a task"))
        #expect(NoteBodyClassifier.isEditableAsPlainText("Just some text"))
    }

    @Test("Structural HTML is editable and preserves line breaks")
    func structuralHTML() {
        let body = "<div>Hello</div><div>world</div>"
        #expect(!NoteBodyClassifier.isPlainText(body))
        #expect(NoteBodyClassifier.isStructurallyPlain(body))
        #expect(NoteBodyClassifier.isEditableAsPlainText(body))
        #expect(NoteBodyClassifier.displayText(body) == "Hello\nworld")
    }

    @Test("Rich content is read-only")
    func richContent() {
        #expect(!NoteBodyClassifier.isEditableAsPlainText("<h1>Title</h1>"))
        #expect(!NoteBodyClassifier.isEditableAsPlainText("<b>bold</b>"))
        #expect(!NoteBodyClassifier.isEditableAsPlainText("<img src=\"x\">"))
        #expect(!NoteBodyClassifier.isEditableAsPlainText("<ul><li>item</li></ul>"))
    }

    @Test("Stripping preserves line breaks and decodes entities")
    func stripping() {
        let stripped = NoteBodyClassifier.strippedForDisplay("<div>Hi &amp; bye<br>there</div>")
        #expect(stripped == "Hi & bye\nthere")
    }

    @Test("Structural HTML from Apple Notes preserves blank lines")
    func appleNotesStructuralHTML() {
        let body = "<div>Title</div>\n<div>alpha</div>\n<div><br></div>\n<div>beta &amp gamma</div>\n"
        #expect(NoteBodyClassifier.displayText(body) == "Title\nalpha\n\nbeta & gamma")
    }

    @Test("Writing HTML preserves line structure and escapes text")
    func writingHTML() {
        let body = "Title & <Plan>\r\nfirst\n\nlast"
        let html = NoteBodyClassifier.htmlForWriting(body)
        #expect(html == "<div>Title &amp; &lt;Plan&gt;</div><div>first</div><div><br></div><div>last</div>")
        #expect(NoteBodyClassifier.displayText(html) == "Title & <Plan>\nfirst\n\nlast")
    }

    @Test("Writing HTML preserves leading and trailing blank lines")
    func writingHTMLPreservesBoundaryBlankLines() {
        let body = "\nTitle\n"
        let appleNotesBody = "<div><br></div>\n<div>Title</div>\n<div><br></div>\n"
        #expect(NoteBodyClassifier.htmlForWriting(body) == "<div><br></div><div>Title</div><div><br></div>")
        #expect(NoteBodyClassifier.displayText(appleNotesBody) == body)
    }
}
