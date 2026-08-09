import SwiftUI

/// Single-note editor with edit and preview modes.
struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if appState.selectedNoteID != nil {
                editor()
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
    private func editor() -> some View {
        VStack(spacing: 0) {
            editorToolbar
            if appState.noteIsReadOnly {
                ReadOnlyEditorView()
            } else if appState.editorMode == .edit {
                NoteBodyTextEditor()
            } else {
                NoteBodyPreviewView()
            }
            statusBar
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            if !appState.noteIsReadOnly {
                Picker(
                    "View",
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
                .frame(width: 124)
            }
            Spacer()

            Button {
                Task { await appState.syncFromNotesNow() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.iconOnly)
                    .overlay {
                        if appState.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
            .help("Sync from Apple Notes")
            .disabled(appState.isSyncing)

            Button {
                appState.openSelectedNoteInNotes()
            } label: {
                Label("Open in Apple Notes", systemImage: "arrow.up.forward.app")
                    .labelStyle(.iconOnly)
            }
            .help("Open in Apple Notes")
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.secondaryColor.opacity(0.08))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.secondaryColor.opacity(0.06))
    }

    private var theme: Theme { settings.activeTheme() }
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
