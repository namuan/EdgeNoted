import SwiftUI

/// Rendered preview of the note body: interactive checklists, hex color
/// chips, and plain paragraphs.
struct NoteBodyPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(Array(NoteBodyRenderer.lines(of: appState.draftBody).enumerated()), id: \.offset) {
                    index,
                    line in
                    lineView(line, at: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder
    private func lineView(_ line: String, at index: Int) -> some View {
        if NoteBodyRenderer.isChecklistLine(line) {
            Button {
                appState.previewToggledChecklist(lineIndex: index)
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: NoteBodyRenderer.isChecked(line) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(
                            NoteBodyRenderer.isChecked(line) ? theme.secondaryColor : theme.accentColor
                        )
                    renderedText(NoteBodyRenderer.checklistText(line))
                        .strikethrough(NoteBodyRenderer.isChecked(line), color: theme.secondaryColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        } else if line.isEmpty {
            Spacer()
                .frame(height: 4)
        } else {
            renderedText(line)
        }
    }

    private func renderedText(_ text: String) -> some View {
        Text(attributed(text))
            .foregroundStyle(theme.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Builds an attributed string where `#rrggbb` tokens become colored,
    /// monospaced chips and everything else is plain body text.
    private func attributed(_ line: String) -> AttributedString {
        var result = AttributedString()
        for segment in NoteBodyRenderer.segments(of: line) {
            var part = AttributedString(segment.text)
            if segment.isHexColor {
                part.font = .body.monospaced()
                if let color = ColorTokenParser.color(fromHex: segment.text) {
                    part.foregroundColor = color
                }
            }
            result += part
        }
        return result
    }

    private var theme: Theme { settings.activeTheme() }
}
