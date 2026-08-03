import ServiceManagement
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            NoteSettingsTab()
                .tabItem { Label("Note", systemImage: "note.text") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            SnippetsSettingsTab()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            AutomationSettingsTab()
                .tabItem { Label("Automation", systemImage: "apple.terminal") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 420)
        .environment(settings)
        .environment(appState)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Invocation") {
                HotKeySettingRow()
                Toggle("Hot Side (mouse to screen edge)", isOn: $settings.hotSideEnabled)
                Picker("Screen Edge", selection: $settings.hotSideEdge) {
                    ForEach(ScreenEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .disabled(!settings.hotSideEnabled)
                LabeledContent("Edge sensitivity") {
                    Slider(value: $settings.hotSideThreshold, in: 2...20, step: 1)
                        .frame(width: 160)
                }
                .disabled(!settings.hotSideEnabled)
                LabeledContent("Auto-hide delay (s)") {
                    Slider(value: $settings.autoHideDelay, in: 0.5...6, step: 0.5)
                        .frame(width: 160)
                }
            }
            Section("Panel") {
                LabeledContent("Panel width") {
                    Slider(value: $settings.panelWidth, in: 320...700, step: 10)
                        .frame(width: 160)
                }
                LabeledContent("Panel height") {
                    Slider(value: $settings.panelHeight, in: 400...900, step: 10)
                        .frame(width: 160)
                }
                LabeledContent("Sync check every") {
                    Picker("", selection: $settings.pollInterval) {
                        Text("2 s").tag(2.0)
                        Text("5 s").tag(5.0)
                        Text("10 s").tag(10.0)
                        Text("30 s").tag(30.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Registration requires a properly installed app bundle.
                            settings.launchAtLogin = false
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            appState.coordinator?.applySettings()
        }
    }
}

private struct HotKeySettingRow: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState
    @State private var recorder = HotKeyRecorder()
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text("Global shortcut")
            Spacer()
            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "Press keys…" : settings.hotKeyDescription)
                    .frame(minWidth: 110)
            }
            .onChange(of: isRecording) { _, recording in
                if recording {
                    recorder.begin { keyCode, flags in
                        settings.hotKeyCode = keyCode
                        settings.hotKeyCommand = flags.contains(.command)
                        settings.hotKeyOption = flags.contains(.option)
                        settings.hotKeyControl = flags.contains(.control)
                        settings.hotKeyShift = flags.contains(.shift)
                        isRecording = false
                        appState.coordinator?.applySettings()
                    }
                } else {
                    recorder.end()
                }
            }
        }
    }
}

// MARK: - Note

private struct NoteSettingsTab: View {
    private static let notesFolderName = "Notes"

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var folders: [NotesFolder] = []
    @State private var notesByFolder: [String: [NoteSummary]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading your notes…")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") {
                            Task { await loadNotes() }
                        }
                    }
                } else {
                    Picker("Displayed note", selection: noteSelection) {
                        Text("None").tag(nil as String?)
                        ForEach(folders) { folder in
                            Section(folder.name) {
                                ForEach(notesByFolder[folder.name] ?? []) { note in
                                    Text(note.name).tag(note.id as String?)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Displayed note")
            } footer: {
                Text(
                    "The panel shows exactly this one note. Pick a different note "
                        + "here to change what the panel displays."
                )
            }
        }
        .formStyle(.grouped)
        .task { await loadNotes() }
    }

    private var noteSelection: Binding<String?> {
        Binding(
            get: { settings.configuredNoteID },
            set: { newValue in
                settings.configuredNoteID = newValue
                updateConfiguredNoteMetadata(for: newValue)
                appState.reloadConfiguredNote()
            }
        )
    }

    /// Keeps the stored folder name and display name in sync with the chosen
    /// note so metadata can resolve the real folder ID later.
    private func updateConfiguredNoteMetadata(for noteID: String?) {
        guard let noteID else {
            settings.configuredNoteFolderName = nil
            settings.configuredNoteName = nil
            return
        }
        for folder in folders {
            guard let notes = notesByFolder[folder.name] else { continue }
            if let note = notes.first(where: { $0.id == noteID }) {
                settings.configuredNoteFolderName = folder.name
                settings.configuredNoteName = note.name
                return
            }
        }
        settings.configuredNoteFolderName = nil
        settings.configuredNoteName = nil
    }

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedFolders = try await appState.notes.fetchFolders()
            let notesFolders = loadedFolders.filter { $0.name == Self.notesFolderName }
            var loadedByFolder: [String: [NoteSummary]] = [:]
            for folder in notesFolders {
                let notes = try await appState.notes.fetchNotes(folderName: folder.name)
                loadedByFolder[folder.name] = notes
            }
            folders = notesFolders
            notesByFolder = loadedByFolder
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                ForEach(Theme.builtins) { theme in
                    themeRow(theme)
                }
                ForEach(settings.customThemes) { theme in
                    customThemeRow(theme)
                }
                Button("Add Custom Theme") {
                    _ = settings.addCustomTheme()
                }
            }
            Section("Note Colors") {
                Picker("Style", selection: $settings.noteColorMode) {
                    ForEach(NoteColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func themeRow(_ theme: Theme) -> some View {
        Button {
            settings.themeName = theme.id
        } label: {
            HStack {
                swatches(theme)
                Text(theme.name)
                Spacer()
                if settings.themeName == theme.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func customThemeRow(_ theme: Theme) -> some View {
        HStack {
            Button {
                settings.themeName = theme.id
            } label: {
                HStack {
                    swatches(theme)
                    Text(theme.name)
                    Spacer()
                    if settings.themeName == theme.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(theme.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Duplicate") {
                    settings.duplicateCustomTheme(id: theme.id)
                }
                Button("Delete", role: .destructive) {
                    settings.deleteCustomTheme(id: theme.id)
                }
                Divider()
                ColorPicker("Accent", selection: colorBinding(theme, keyPath: \.accentHex), supportsOpacity: false)
                ColorPicker(
                    "Background",
                    selection: colorBinding(theme, keyPath: \.backgroundHex),
                    supportsOpacity: false
                )
                ColorPicker("Text", selection: colorBinding(theme, keyPath: \.textHex), supportsOpacity: false)
                ColorPicker(
                    "Secondary",
                    selection: colorBinding(theme, keyPath: \.secondaryHex),
                    supportsOpacity: false
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func swatches(_ theme: Theme) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2).fill(theme.accentColor).frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 2).fill(theme.backgroundColor).frame(width: 14, height: 14)
                .overlay { RoundedRectangle(cornerRadius: 2).stroke(.secondary.opacity(0.4)) }
            RoundedRectangle(cornerRadius: 2).fill(theme.textColor).frame(width: 14, height: 14)
        }
    }

    private func colorBinding(_ theme: Theme, keyPath: KeyPath<Theme, String>) -> Binding<Color> {
        Binding(
            get: {
                ColorTokenParser.color(fromHex: theme[keyPath: keyPath]) ?? .clear
            },
            set: { newColor in
                settings.updateCustomTheme(id: theme.id, hexField: keyPath, to: newColor)
            }
        )
    }
}

// MARK: - Snippets

private struct SnippetsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt) private var snippets: [Snippet]
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        Form {
            Section("New snippet") {
                TextField("Title", text: $title)
                TextEditor(text: $text)
                    .frame(height: 70)
                HStack {
                    Spacer()
                    Button("Add") {
                        guard !title.isEmpty else { return }
                        MetaStore.addSnippet(title: title, text: text, in: modelContext)
                        title = ""
                        text = ""
                    }
                    .disabled(title.isEmpty)
                }
            }
            Section("Saved") {
                if snippets.isEmpty {
                    Text("No snippets yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snippets) { snippet in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(snippet.title)
                                Text(snippet.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                MetaStore.deleteSnippet(snippet, in: modelContext)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation

private struct AutomationSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Notes & Reminders integration")
                .font(.headline)
            Text(
                "EdgeNoted reads and writes your notes and reminders through Apple's "
                    + "Apple Events (AppleScript). On first use, macOS asks you to allow "
                    + "EdgeNoted to control Notes and Reminders."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Test Connection") {
                    test()
                }
                .disabled(isTesting)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let testResult {
                Text(testResult)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let automationError = appState.automationError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(automationError)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button("Open Privacy & Security") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func test() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let folders = try await appState.notes.fetchFolders()
                let lists = try await appState.reminders.fetchLists()
                testResult = "Connected. Found \(folders.count) Notes folder(s) and \(lists.count) Reminders list(s)."
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 36))
                VStack(alignment: .leading) {
                    Text("EdgeNoted")
                        .font(.title2.bold())
                    Text("Version 1.6")
                        .foregroundStyle(.secondary)
                }
            }
            Text(
                "A lightweight, always-available companion for your Apple Notes and Reminders. "
                    + "Notes are edited directly in Apple Notes with bidirectional sync; local data "
                    + "is limited to presentation preferences (pins, order, colors, themes, snippets)."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "Limitations: Apple Notes exposes only plain text through AppleScript, so notes "
                    + "containing rich formatting are shown read-only, and attachments cannot be "
                    + "synced. Reordering inside Apple Notes itself is not supported."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            LoggingSection()

            Spacer()
        }
        .padding(20)
    }
}

/// Shows where log files live and opens the folder in Finder.
private struct LoggingSection: View {
    @State private var logDirectory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logs")
                .font(.headline)
            HStack {
                Text(logDirectory ?? "Resolving log directory…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open Logs Folder") {
                    openLogsFolder()
                }
                .controlSize(.small)
                .disabled(logDirectory == nil)
            }
            Text("Diagnostics are written to rolling files (EdgeNoted.log, EdgeNoted-1.log, …).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .task {
            logDirectory = await AppLogger.shared.activeDirectoryPath()
        }
    }

    private func openLogsFolder() {
        guard let logDirectory else { return }
        let url = URL(fileURLWithPath: logDirectory, isDirectory: true)
        NSWorkspace.shared.open(url)
    }
}
