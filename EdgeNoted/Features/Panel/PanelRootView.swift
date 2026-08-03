import AppKit
import SwiftUI

/// Root content hosted inside the edge panel.
struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView()
            Rectangle()
                .fill(theme.secondaryColor.opacity(0.25))
                .frame(height: 1)
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
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.secondaryColor.opacity(0.35), lineWidth: 1)
        }
        .tint(theme.accentColor)
        .onExitCommand { appState.hidePanel() }
    }

    private var theme: Theme { settings.activeTheme() }
}

/// Top bar: section switcher, settings, hide.
private struct PanelHeaderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Section", selection: $appState.activeSection) {
                    ForEach(AppState.Section.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)

                Spacer()

                Button {
                    appState.coordinator?.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    appState.hidePanel()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Hide (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }
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
                Button("Take Theirs") { appState.resolveConflictTakeRemote() }
                Button("Open in Notes") { appState.openSelectedNoteInNotes() }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
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
                if appState.automationDenied {
                    Button("Open Privacy & Security") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}
