import SwiftData
import SwiftUI

/// Single-note editor: title, edit/preview modes, fold, colors, export.
struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt) private var snippets: [Snippet]

    var body: some View {
        Group {
            if let noteID = appState.selectedNoteID {
                editor(noteID: noteID)
            } else {
                ContentUnavailableView(
                    "No note configured",
                    systemImage: "note.text",
                    description: Text("Choose a note in Settings to display it here.")
                )
            }
        }
    }

    @ViewBuilder
    private func editor(noteID: String) -> some View {
        let meta = noteMetas.first { $0.noteID == noteID }
        VStack(spacing: 0) {
            titleBar(meta: meta)
            Rectangle()
                .fill(theme.secondaryColor.opacity(0.25))
                .frame(height: 1)
            if meta?.isFolded == true {
                FoldedEditorBar()
            } else if appState.noteIsReadOnly {
                ReadOnlyEditorView()
            } else if appState.editorMode == .edit {
                NoteBodyTextEditor()
            } else {
                NoteBodyPreviewView()
            }
            statusBar
        }
    }

    private var noteMetas: [NoteMeta] {
        (try? modelContext.fetch(FetchDescriptor<NoteMeta>())) ?? []
    }

    private func titleBar(meta: NoteMeta?) -> some View {
        HStack(spacing: 8) {
            NoteTitleField()
            Spacer()
            if !appState.noteIsReadOnly {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { appState.editorMode },
                        set: { appState.editorMode = $0 }
                    )
                ) {
                    Text("Edit").tag(AppState.EditorMode.edit)
                    Text("Preview").tag(AppState.EditorMode.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }
            Button {
                appState.toggleFold()
            } label: {
                Image(systemName: meta?.isFolded == true ? "chevron.right.circle" : "chevron.down.circle")
            }
            .help(meta?.isFolded == true ? "Expand note" : "Fold note")

            Button {
                appState.togglePin()
            } label: {
                Image(systemName: meta?.isPinned == true ? "pin.fill" : "pin")
            }
            .help(meta?.isPinned == true ? "Unpin note" : "Pin note")

            Menu {
                ForEach(AppColor.noteColors, id: \.name) { item in
                    Button {
                        appState.setNoteColor(item.hex.isEmpty ? nil : item.hex)
                    } label: {
                        if item.hex.isEmpty {
                            Text(item.name)
                        } else {
                            Label(item.name, systemImage: "circle.fill")
                                .foregroundStyle(AppColor.color(forHex: item.hex) ?? .secondary)
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .help("Note color")

            if !snippets.isEmpty && !appState.noteIsReadOnly {
                Menu {
                    ForEach(snippets) { snippet in
                        Button(snippet.title) {
                            appState.insertSnippet(snippet.text)
                        }
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .help("Insert snippet")
            }

            Button {
                exportAsImage()
            } label: {
                Image(systemName: "photo")
            }
            .help("Export as image")

            Button {
                appState.openSelectedNoteInNotes()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Open in Apple Notes")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if appState.isSaving {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else if let saved = appState.lastSavedAt {
                Label("Saved \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            if appState.noteIsReadOnly {
                Label("Read-only", systemImage: "lock")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var theme: Theme { settings.activeTheme() }

    private func exportAsImage() {
        NoteImageExporter.export(title: appState.draftTitle, body: appState.draftBody, theme: theme)
    }
}

/// Title text field that marks the draft dirty on change.
private struct NoteTitleField: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var appState = appState
        TextField("Title", text: $appState.draftTitle)
            .textFieldStyle(.plain)
            .font(.headline)
            .onChange(of: appState.draftTitle) { _, _ in
                appState.titleChanged()
            }
            .foregroundStyle(settings.activeTheme().textColor)
    }
}

/// Plain-text editor bound to the draft body.
private struct NoteBodyTextEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var appState = appState
        TextEditor(text: $appState.draftBody)
            .font(.body)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(settings.activeTheme().backgroundColor)
            .foregroundStyle(settings.activeTheme().textColor)
            .onChange(of: appState.draftBody) { _, _ in
                appState.bodyChanged()
            }
    }
}

/// Collapsed view when the note is folded.
private struct FoldedEditorBar: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right.circle")
            Text(appState.draftTitle.isEmpty ? "Note folded" : appState.draftTitle)
                .lineLimit(1)
                .foregroundStyle(theme.secondaryColor)
            Spacer()
            Button("Expand") { appState.toggleFold() }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
    }

    private var theme: Theme { settings.activeTheme() }
}

/// Read-only display for notes containing rich content that text editing
/// would destroy.
private struct ReadOnlyEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("This note contains formatting that can't be safely edited as plain text.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryColor)
                Spacer()
                Menu {
                    Button("Open in Apple Notes") { appState.openSelectedNoteInNotes() }
                    Button("Convert to plain text") { appState.convertToPlainText() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(8)
            .background(theme.secondaryColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                Text(NoteBodyClassifier.strippedForDisplay(appState.draftBody))
                    .font(.body)
                    .foregroundStyle(theme.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var theme: Theme { settings.activeTheme() }
}
