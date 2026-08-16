import SwiftUI

/// Reminders: a compact add row with list picker above the unified due list.
struct RemindersSectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            addRow
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(height: 1)
            reminderList
        }
        // The panel gives each section the full available height. Keep this
        // section's intrinsic content pinned to the top instead of allowing
        // SwiftUI to vertically center it and leave a large blank band above.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A dedicated capture area keeps creating a reminder separate from the due list.
    private var addRow: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("New reminder", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(settings.activeTheme().accentColor)
                Spacer()
                listMenu
            }

            HStack(spacing: 8) {
                TextField("What needs doing?", text: $appState.quickCaptureText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(appState.isCreatingReminder || appState.reminderLists.isEmpty)
                    .onSubmit { appState.quickCapture() }

                Button("Add") { appState.quickCapture() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        appState.quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || appState.isCreatingReminder
                            || appState.reminderLists.isEmpty
                    )
                    .overlay {
                        if appState.isCreatingReminder {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .focusEffectDisabled()
            }

            HStack(spacing: 6) {
                Text("Due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("Due", selection: $appState.quickCaptureDueDate)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .disabled(appState.isCreatingReminder || appState.reminderLists.isEmpty)
                    .help("Due date (default: one hour from now)")
                    .focusEffectDisabled()
                if let listName = appState.lastCreatedListName {
                    Spacer()
                    Label("Added to \(listName)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(settings.activeTheme().accentColor)
                }
            }
        }
        .padding(16)
        .background(settings.activeTheme().secondaryColor.opacity(0.08))
    }

    private var listMenu: some View {
        Menu {
            ForEach(appState.reminderLists) { list in
                Button {
                    appState.quickCaptureListID = list.id
                } label: {
                    if list.id == appState.quickCaptureListID {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
        } label: {
            Label(appState.selectedQuickCaptureListName, systemImage: "list.bullet")
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .disabled(appState.reminderLists.isEmpty)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var reminderList: some View {
        if appState.displayedReminderItems.isEmpty {
            ContentUnavailableView(
                "No reminders due",
                systemImage: "checklist",
                description: Text("No incomplete reminders are overdue or due today in any list.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(appState.displayedReminderItems) { item in
                        ReminderRow(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// One reminder row: checkbox, editable title, due date, priority, actions.
private struct ReminderRow: View {
    let item: ReminderItem
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var draftName: String

    init(item: ReminderItem) {
        self.item = item
        _draftName = State(initialValue: item.name)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                appState.toggleReminder(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? theme.secondaryColor : theme.accentColor)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "Mark incomplete" : "Complete")
            .focusEffectDisabled()

            VStack(alignment: .leading, spacing: 2) {
                TextField("Reminder", text: $draftName)
                    .textFieldStyle(.plain)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? theme.secondaryColor : theme.textColor)
                    .onSubmit {
                        appState.updateReminderName(item, to: draftName)
                    }
                HStack(spacing: 8) {
                    if let dueEpoch = item.dueEpoch {
                        Label(
                            Self.dateFormatter.string(from: Date(timeIntervalSince1970: dueEpoch)),
                            systemImage: "calendar"
                        )
                        .font(.caption2)
                        .foregroundStyle(isOverdue(dueEpoch) ? .red : theme.secondaryColor)
                    }
                    if !item.listName.isEmpty {
                        Label(item.listName, systemImage: "list.bullet")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryColor)
                    }
                    if item.priorityLevel != .none {
                        Text(item.priorityLevel.title)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(priorityColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(priorityColor)
                    }
                }
            }

            Spacer()

            Menu {
                Section("Due") {
                    Button("Today") {
                        appState.updateReminderDetails(item, dueEpoch: Self.startOfToday, priority: item.priority)
                    }
                    Button("Tomorrow") {
                        appState.updateReminderDetails(
                            item,
                            dueEpoch: Self.startOfToday + 86_400,
                            priority: item.priority
                        )
                    }
                    Button("Next Week") {
                        appState.updateReminderDetails(
                            item,
                            dueEpoch: Self.startOfToday + 7 * 86_400,
                            priority: item.priority
                        )
                    }
                    if item.dueEpoch != nil {
                        Button("Clear Due Date") {
                            appState.clearReminderDueDate(item)
                        }
                    }
                }
                Section("Priority") {
                    ForEach(ReminderPriority.allCases) { level in
                        Button {
                            appState.updateReminderDetails(item, dueEpoch: item.dueEpoch, priority: level.rawValue)
                        } label: {
                            if level == item.priorityLevel {
                                Label(level.title, systemImage: "checkmark")
                            } else {
                                Text(level.title)
                            }
                        }
                    }
                }
                Section {
                    Button("Open in Reminders", systemImage: "arrow.up.forward.app") {
                        appState.openRemindersApp()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        appState.deleteReminder(item)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusEffectDisabled()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(.rect)
        .contextMenu {
            Button(item.isCompleted ? "Mark Incomplete" : "Complete") {
                appState.toggleReminder(item)
            }
            Button("Open in Reminders", systemImage: "arrow.up.forward.app") {
                appState.openRemindersApp()
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                appState.deleteReminder(item)
            }
        }
    }

    private var theme: Theme { settings.activeTheme() }

    private var priorityColor: Color {
        switch item.priorityLevel {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        case .none: .secondary
        }
    }

    private func isOverdue(_ dueEpoch: TimeInterval) -> Bool {
        dueEpoch < Calendar.current.startOfDay(for: .now).timeIntervalSince1970 && !item.isCompleted
    }

    private static var startOfToday: TimeInterval {
        Calendar.current.startOfDay(for: .now).timeIntervalSince1970
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
