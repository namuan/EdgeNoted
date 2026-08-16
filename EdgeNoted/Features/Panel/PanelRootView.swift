import AppKit
import SwiftUI

/// Root content hosted inside the edge panel.
struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView()
            Group {
                switch appState.activeSection {
                case .notes: NotesSectionView()
                case .reminders: RemindersSectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if appState.conflict != nil {
                ConflictBannerView()
            }
            if let automationError = appState.automationError {
                AutomationErrorBar(message: automationError)
            }
        }
        .frame(width: settings.panelWidth)
        .frame(maxHeight: .infinity)
        .background(theme.backgroundColor.opacity(0.96))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.secondaryColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .tint(theme.accentColor)
        // The system focus halo is visually much stronger than this compact
        // utility surface. Buttons remain reachable by keyboard and expose
        // their labels to VoiceOver, without the oversized ring.
        .focusEffectDisabled()
        .onExitCommand { appState.hidePanel() }
    }

    private var theme: Theme { settings.activeTheme() }
}

/// A compact identity-first header for the active workspace.
private struct PanelHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var appState = appState
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Workspace", selection: $appState.activeSection) {
                Label("Notes", systemImage: "note.text").tag(AppState.Section.notes)
                Label("Reminders", systemImage: "checklist").tag(AppState.Section.reminders)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .focusEffectDisabled()

            if appState.activeSection == .reminders {
                reminderHorizonMenu
            }

            Menu {
                Button("Settings…", systemImage: "gearshape") {
                    appState.coordinator?.openSettings()
                }
                Divider()
                Button("Hide", systemImage: "chevron.right") {
                    appState.hidePanel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Quit EdgeNoted", systemImage: "power", role: .destructive) {
                    appState.coordinator?.requestQuit()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .focusEffectDisabled()
            .help("More actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.backgroundColor.opacity(0.72))
    }

    private var title: String {
        switch appState.activeSection {
        case .notes:
            appState.draftTitle.isEmpty ? "Notes" : appState.draftTitle
        case .reminders:
            "Reminders"
        }
    }

    private var subtitle: String {
        switch appState.activeSection {
        case .notes:
            appState.noteIsReadOnly ? "Apple Notes · Read-only" : "Apple Notes"
        case .reminders:
            settings.reminderHorizon.subtitle
        }
    }

    /// Lets the user widen or narrow how far ahead the Reminders list looks.
    /// Labeled with the current selection so the control always states its state.
    private var reminderHorizonMenu: some View {
        Menu {
            ForEach(ReminderHorizon.allCases) { horizon in
                Button {
                    settings.reminderHorizon = horizon
                } label: {
                    if horizon == settings.reminderHorizon {
                        Label(horizon.title, systemImage: "checkmark")
                    } else {
                        Text(horizon.title)
                    }
                }
            }
        } label: {
            Label(settings.reminderHorizon.shortTitle, systemImage: "calendar")
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show: \(settings.reminderHorizon.title)")
        .focusEffectDisabled()
    }

    private var theme: Theme { settings.activeTheme() }
}

/// Shown when the remote note changed while local edits were pending.
private struct ConflictBannerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "This note changed in Apple Notes while you were editing.",
                systemImage: "exclamationmark.triangle.fill"
            )
            HStack(spacing: 10) {
                Button("Keep Mine") { appState.resolveConflictKeepMine() }
                    .focusEffectDisabled()
                Button("Take Theirs") { appState.resolveConflictTakeRemote() }
                    .focusEffectDisabled()
                Button("Open in Notes") { appState.openSelectedNoteInNotes() }
                    .focusEffectDisabled()
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }
}

/// Persistent bar shown when automation permission is missing or Notes/Reminders
/// is unavailable. Actionable so the just-in-time permission flow can be
/// completed without leaving the panel.
private struct AutomationErrorBar: View {
    let message: String
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "apple.terminal")
                Text(message)
                    .font(.caption)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("Retry") { appState.retryAutomation() }
                    .disabled(appState.isLoading)
                    .focusEffectDisabled()
                if appState.automationDenied {
                    Button("Open Privacy & Security") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .focusEffectDisabled()
                }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }
}
