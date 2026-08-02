import AppKit
import SwiftUI

/// Exports the currently displayed note as a PNG image via NSSavePanel.
@MainActor
enum NoteImageExporter {
    static func export(title: String, body: String, theme: Theme) {
        Log.info(
            "Note export requested",
            category: .export,
            metadata: [
                "bodyBytes": String(body.utf8.count)
            ]
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(title.isEmpty ? "Note" : title).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                Log.info("Note export cancelled", category: .export)
                return
            }

            let view = ExportNoteView(title: title, noteBody: body, theme: theme)
                .frame(width: 800)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 800, height: nil)

            guard let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                Log.error("Note export failed to render", category: .export)
                NSSound.beep()
                return
            }
            do {
                try png.write(to: url)
                Log.info(
                    "Note export saved",
                    category: .export,
                    metadata: [
                        "bytes": String(png.count),
                        "directory": url.deletingLastPathComponent().path,
                    ]
                )
            } catch {
                Log.error("Note export write failed", category: .export)
            }
        }
    }
}

/// Dedicated view rendered to an image; separate from the live editor so the
/// export output is stable and self-contained.
struct ExportNoteView: View {
    let title: String
    let noteBody: String
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title.bold())
                .foregroundStyle(theme.textColor)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(NoteBodyRenderer.lines(of: noteBody).enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(theme.backgroundColor)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if NoteBodyRenderer.isChecklistLine(line) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: NoteBodyRenderer.isChecked(line) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(theme.accentColor)
                renderedText(NoteBodyRenderer.checklistText(line))
                    .strikethrough(NoteBodyRenderer.isChecked(line))
            }
        } else if line.isEmpty {
            Spacer().frame(height: 6)
        } else {
            renderedText(line)
        }
    }

    private func renderedText(_ text: String) -> some View {
        var result = AttributedString()
        for segment in NoteBodyRenderer.segments(of: text) {
            var part = AttributedString(segment.text)
            if segment.isHexColor {
                part.font = .body.monospaced()
                if let color = ColorTokenParser.color(fromHex: segment.text) {
                    part.foregroundColor = color
                }
            }
            result += part
        }
        return Text(result)
            .foregroundStyle(theme.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
