import AppKit
import Foundation
import Observation
import SwiftData

/// Central observable state for the panel UI. Owns the selected note/reminder,
/// the editor draft, and the synchronization loop with Apple Notes.
@MainActor
@Observable
final class AppState {
    enum Section: String, CaseIterable, Identifiable {
        case notes
        case reminders

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum EditorMode: String, CaseIterable {
        case edit
        case preview
    }

    struct ConflictBanner: Identifiable, Equatable {
        let id = UUID()
        let remoteBody: String
    }

    // MARK: Dependencies

    let notes: any NotesService
    let reminders: any RemindersService
    let settings: SettingsStore
    let modelContainer: ModelContainer
    weak var coordinator: ApplicationCoordinator?

    // MARK: Presentation

    var isPanelVisible = false
    var activeSection: Section = .notes
    var isLoading = false
    var statusMessage: String?
    var automationDenied = false
    var automationError: String?
    var automationNeedsAppLaunch = false

    // MARK: Notes browsing

    var folders: [NotesFolder] = []
    var notesList: [NoteSummary] = []
    var searchText = "" {
        didSet { searchDebouncer?.schedule() }
    }

    var searchResults: [NoteSummary] = []
    var selectedFolderName: String?
    var selectedNoteID: String?

    // MARK: Note editor

    var draftTitle = ""
    var draftBody = ""
    var editorMode: EditorMode = .edit
    var noteIsReadOnly = false
    var isSaving = false
    var lastSavedAt: Date?
    var conflict: ConflictBanner?

    // MARK: Reminders

    var reminderLists: [ReminderList] = []
    var selectedListName: String?
    var reminderItems: [ReminderItem] = []
    var selectedReminderID: String?
    var quickCaptureText = ""

    // MARK: Private state

    private var sync = NoteDraftSync()
    private var pollTask: Task<Void, Never>?
    private var saveDebouncer: Debouncer?
    private var searchDebouncer: Debouncer?
    private var lastRemoteMtime: TimeInterval?
    /// The note id with unsaved edits, so a pending save survives switching
    /// notes and never lands on the wrong note.
    private var pendingSaveNoteID: String?
    /// Guards against out-of-order note loads when the user switches quickly.
    private var noteLoadSequence = 0

    init(
        notes: any NotesService,
        reminders: any RemindersService,
        settings: SettingsStore,
        modelContainer: ModelContainer = PersistenceController.container
    ) {
        self.notes = notes
        self.reminders = reminders
        self.settings = settings
        self.modelContainer = modelContainer
        self.saveDebouncer = nil
        self.searchDebouncer = nil
        // Self is now fully initialized; safe for closures to capture it.
        self.saveDebouncer = Debouncer(delay: 1.2) { [weak self] in
            await self?.saveNoteNow()
        }
        self.searchDebouncer = Debouncer(delay: 0.35) { [weak self] in
            await self?.performSearch()
        }
    }

    // MARK: - Startup

    /// True once the initial service load has been attempted. Startup is
    /// deferred until the user first opens the panel so the automation
    /// permission prompt appears in context rather than at app launch.
    private var didRunStartup = false

    /// Runs the initial service load exactly once (on first panel show).
    func ensureStarted() async {
        guard !didRunStartup else { return }
        didRunStartup = true
        Log.info("Initial service load requested", category: .lifecycle)
        await startup()
    }

    /// Re-attempts the connection after the user grants access or fixes an
    /// error, e.g. from the panel's error bar.
    func retryAutomation() {
        guard !isLoading else { return }
        automationDenied = false
        let needsAppLaunch = automationNeedsAppLaunch
        Log.info(
            "Retry automation requested",
            category: .sync,
            metadata: [
                "launchApps": String(needsAppLaunch)
            ]
        )
        Task { [weak self] in
            guard let self else { return }
            if needsAppLaunch {
                self.launchAutomationApps()
                try? await Task.sleep(for: .milliseconds(750))
            }
            guard !Task.isCancelled else { return }
            await self.startup()
        }
    }

    func startup() async {
        isLoading = true
        automationError = nil
        let startedAt = Date()
        do {
            let (loadedFolders, loadedLists) = try await loadServicesWithLaunchRetry()
            folders = loadedFolders
            reminderLists = loadedLists
            if selectedListName == nil {
                selectedListName = loadedLists.first?.name
            }
            await loadFoldersAndNotes()
            if let selectedListName {
                await loadReminders(listName: selectedListName)
            }
            statusMessage = nil
            automationNeedsAppLaunch = false
            Log.info(
                "Startup completed",
                category: .sync,
                metadata: [
                    "folders": String(loadedFolders.count),
                    "lists": String(loadedLists.count),
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
        } catch {
            handleServiceError(error)
            Log.error(
                "Startup failed",
                category: .sync,
                metadata: [
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000))
                ]
            )
        }
        isLoading = false
    }

    /// Loads the folder/list indexes, making sure Notes and Reminders are
    /// running first. In the sandbox the AppleScript helper cannot launch
    /// target apps itself (which surfaces as -600 "Application isn't
    /// running"), so EdgeNoted launches them via LaunchServices and retries a
    /// few times while they start up.
    private func loadServicesWithLaunchRetry() async throws -> ([NotesFolder], [ReminderList]) {
        launchAutomationApps()
        Log.info("Ensuring Notes and Reminders are running", category: .bridge)
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                Log.info("Retrying service load", category: .bridge, metadata: ["attempt": String(attempt)])
                try? await Task.sleep(for: .milliseconds(900))
                launchAutomationApps()
            }
            do {
                async let folders = notes.fetchFolders()
                async let lists = reminders.fetchLists()
                return try await (folders, lists)
            } catch let error as ScriptError {
                lastError = error
                if case .appNotRunning = error {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? ScriptError.executionFailed("Could not connect to Apple Notes and Reminders")
    }

    private func launchAutomationApps() {
        for bundleIdentifier in ["com.apple.Notes", "com.apple.Reminders"] {
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                )
            else {
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        }
    }

    // MARK: - Notes browsing

    func loadFoldersAndNotes() async {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        do {
            let loadedFolders = try await notes.fetchFolders()
            folders = loadedFolders
            // Re-home any local metadata that still uses folder names as keys.
            MetaStore.migrateFolderNameKeys(loadedFolders, in: modelContainer.mainContext)
            let loaded = try await notes.fetchNotes(folderName: selectedFolderName)
            notesList = loaded
            if let selected = selectedNoteID, !loaded.contains(where: { $0.id == selected }) {
                selectedNoteID = nil
            }
            Log.info(
                "Folder/note index loaded",
                category: .notes,
                metadata: [
                    "folders": String(loadedFolders.count),
                    "notes": String(loaded.count),
                    "folder": selectedFolderName.map { Log.digest($0) } ?? "all",
                ]
            )
        } catch {
            handleServiceError(error)
        }
        isLoading = false
    }

    func selectFolder(_ name: String?) {
        guard selectedFolderName != name else { return }
        selectedFolderName = name
        searchText = ""
        searchResults = []
        Task { await loadFoldersAndNotes() }
    }

    func selectNote(_ id: String?) {
        guard id != selectedNoteID else { return }
        // Persist unsaved edits of the current note before switching, using a
        // snapshot so the async save can't pick up the next note's content.
        // Only a genuinely dirty note is flushed - never an untouched draft.
        if let pending = pendingSaveNoteID, pending != id, sync.isDirty {
            saveDebouncer?.cancel()
            let snapshotTitle = draftTitle
            let snapshotBody = draftBody
            Task { await saveNoteNow(force: true, noteID: pending, title: snapshotTitle, body: snapshotBody) }
        }
        pendingSaveNoteID = nil
        noteLoadSequence += 1
        selectedNoteID = id
        conflict = nil
        guard let id else {
            draftTitle = ""
            draftBody = ""
            noteIsReadOnly = false
            sync = NoteDraftSync()
            pollTask?.cancel()
            return
        }
        Task { await openNote(id) }
    }

    private func openNote(_ id: String) async {
        noteLoadSequence += 1
        let sequence = noteLoadSequence
        isLoading = true
        let startedAt = Date()
        do {
            let detail = try await notes.fetchNote(id: id)
            // A newer selection may have superseded this load.
            guard sequence == noteLoadSequence else { return }
            let displayBody = NoteBodyClassifier.displayText(detail.body)
            selectedNoteID = detail.id
            draftTitle = detail.name
            draftBody = displayBody
            lastRemoteMtime = detail.modificationEpoch
            noteIsReadOnly = !NoteBodyClassifier.isEditableAsPlainText(detail.body)
            conflict = nil
            pendingSaveNoteID = nil
            sync = NoteDraftSync()
            sync.load(remoteBody: displayBody)
            lastSavedAt = Date()
            markOpened(detail)
            startPolling()
            Log.info(
                "Note opened",
                category: .notes,
                metadata: [
                    "noteId": detail.id,
                    "bodyBytes": String(detail.body.utf8.count),
                    "readOnly": String(noteIsReadOnly),
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
        } catch {
            handleServiceError(error)
            Log.error("Failed to open note", category: .notes, metadata: ["noteId": id])
        }
        isLoading = false
    }

    private func markOpened(_ detail: NoteDetail) {
        let context = modelContainer.mainContext
        // Folders are keyed by name in the AppleScript bridge, but local
        // metadata must store the real folder ID, never the folder name.
        guard let folderID = resolvedFolderID else { return }
        let meta = MetaStore.noteMeta(createIfNeededFor: detail.id, folderID: folderID, in: context)
        meta.lastOpenedAt = Date()
        try? context.save()
    }

    /// The real Apple Notes folder ID for the currently selected folder.
    /// - "All Notes" (no folder selected) maps to `""` (the All Notes bucket).
    /// - nil when a folder is selected but not yet resolved from the loaded
    ///   folder list (startup race) - callers must skip rather than write into
    ///   the wrong bucket.
    var resolvedFolderID: String? {
        guard let selectedFolderName else { return "" }
        return folders.first(where: { $0.name == selectedFolderName })?.id
    }

    // MARK: - Note editing

    func titleChanged() {
        markDirty()
    }

    func bodyChanged() {
        markDirty()
    }

    func previewToggledChecklist(lineIndex: Int) {
        guard let updated = NoteBodyRenderer.toggleChecklistItem(in: draftBody, at: lineIndex) else { return }
        draftBody = updated
        markDirty()
    }

    private func markDirty() {
        guard let noteID = selectedNoteID, !noteIsReadOnly else { return }
        sync.edit(localBody: draftBody)
        // pendingSaveNoteID tracks whether there are genuine unsaved edits.
        // Programmatic draft fills (opening a note, adopting a remote change)
        // route through here with an unchanged hash and must not mark the note
        // as needing a save.
        pendingSaveNoteID = sync.isDirty ? noteID : nil
        isSaving = false
        lastSavedAt = nil
        saveDebouncer?.schedule()
    }

    func newNote() {
        Task {
            isLoading = true
            do {
                let detail = try await notes.createNote(title: "Untitled", body: "", folderName: selectedFolderName)
                Log.info(
                    "Note created",
                    category: .notes,
                    metadata: [
                        "noteId": detail.id,
                        "folder": selectedFolderName.map { Log.digest($0) } ?? "all",
                    ]
                )
                selectedNoteID = detail.id
                await loadFoldersAndNotes()
                await openNote(detail.id)
            } catch {
                handleServiceError(error)
                Log.error(
                    "Failed to create note",
                    category: .notes,
                    metadata: ["folder": selectedFolderName.map { Log.digest($0) } ?? "all"]
                )
            }
            isLoading = false
        }
    }

    func convertToPlainText() {
        guard noteIsReadOnly, !draftBody.isEmpty else { return }
        draftBody = NoteBodyClassifier.strippedForDisplay(draftBody)
        noteIsReadOnly = false
        sync = NoteDraftSync()
        sync.load(remoteBody: draftBody)
        Task { await saveNoteNow(force: true) }
    }

    func openSelectedNoteInNotes() {
        guard let selectedNoteID else { return }
        var opened = false
        if let encoded = selectedNoteID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "notes://showNote?identifier=\(encoded)")
        {
            opened = NSWorkspace.shared.open(url)
        }
        if !opened,
            let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes")
        {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: notesURL, configuration: configuration) { _, _ in }
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Reminders") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        }
    }

    // MARK: - Local note metadata

    func togglePin() {
        guard let selectedNoteID, let folderID = resolvedFolderID else { return }
        let context = modelContainer.mainContext
        let meta = MetaStore.noteMeta(
            createIfNeededFor: selectedNoteID,
            folderID: folderID,
            in: context
        )
        MetaStore.setNotePinned(!meta.isPinned, noteID: selectedNoteID, folderID: folderID, in: context)
    }

    func toggleFold() {
        guard let selectedNoteID, let folderID = resolvedFolderID else { return }
        let context = modelContainer.mainContext
        let meta = MetaStore.noteMeta(
            createIfNeededFor: selectedNoteID,
            folderID: folderID,
            in: context
        )
        MetaStore.setNoteFolded(!meta.isFolded, noteID: selectedNoteID, folderID: folderID, in: context)
    }

    func setNoteColor(_ hex: String?) {
        guard let selectedNoteID, let folderID = resolvedFolderID else { return }
        MetaStore.setNoteColor(
            hex,
            noteID: selectedNoteID,
            folderID: folderID,
            in: modelContainer.mainContext
        )
    }

    func insertSnippet(_ text: String) {
        guard !noteIsReadOnly else { return }
        if !draftBody.isEmpty, !draftBody.hasSuffix("\n") {
            draftBody += "\n"
        }
        draftBody += text
        markDirty()
    }

    // MARK: - Save + sync

    /// Saves the draft. `noteID`/`title`/`body` override the current editor
    /// state when saving a snapshot of a previously selected note.
    func saveNoteNow(force: Bool = false, noteID: String? = nil, title: String? = nil, body: String? = nil) async {
        let targetID = noteID ?? pendingSaveNoteID ?? selectedNoteID
        guard let targetID, !noteIsReadOnly else { return }
        guard force || sync.isDirty else { return }
        isSaving = true
        let startedAt = Date()
        do {
            try await notes.updateNote(id: targetID, title: title ?? draftTitle, body: body ?? draftBody)
            if pendingSaveNoteID == targetID {
                pendingSaveNoteID = nil
            }
            if targetID == selectedNoteID {
                sync.submitted(localBody: body ?? draftBody)
                lastSavedAt = Date()
            }
            isSaving = false
            statusMessage = nil
            automationError = nil
            Log.info(
                "Note saved",
                category: .notes,
                metadata: [
                    "noteId": targetID,
                    "bodyBytes": String((body ?? draftBody).utf8.count),
                    "elapsedMs": String(Int(Date().timeIntervalSince(startedAt) * 1000)),
                ]
            )
        } catch {
            isSaving = false
            handleServiceError(error)
            Log.error("Failed to save note", category: .notes, metadata: ["noteId": targetID])
        }
    }

    func flushPendingSave() async {
        saveDebouncer?.cancel()
        // Only flush when there are genuine unsaved edits. Never force-write
        // an untouched (possibly empty) draft, which could wipe note content
        // when the panel hides.
        guard sync.isDirty else { return }
        await saveNoteNow(force: true)
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = max(settings.pollInterval, 1.0)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if self.isPanelVisible || self.sync.isDirty {
                    await self.pollSelectedNote()
                }
            }
        }
    }

    /// Polls the selected note for remote changes. Internal so tests can drive
    /// it directly instead of waiting for the timer.
    func pollSelectedNote() async {
        guard let noteID = selectedNoteID else { return }
        do {
            let detail = try await notes.fetchNote(id: noteID)
            if let remote = detail.modificationEpoch, let local = lastRemoteMtime, remote == local {
                return
            }
            lastRemoteMtime = detail.modificationEpoch
            let displayBody = NoteBodyClassifier.displayText(detail.body)
            let event = sync.observeRemote(body: displayBody)
            switch event {
            case .noChange:
                // Title-only remote change: adopt it when the draft is clean so
                // an in-progress local title edit is never clobbered.
                if !sync.isDirty, detail.name != draftTitle {
                    draftTitle = detail.name
                    Log.info("Remote title adopted", category: .sync, metadata: ["noteId": noteID])
                }
            case .remoteUpdated:
                draftTitle = detail.name
                draftBody = displayBody
                noteIsReadOnly = !NoteBodyClassifier.isEditableAsPlainText(detail.body)
                lastSavedAt = Date()
                conflict = nil
                Log.info(
                    "Remote note change adopted",
                    category: .sync,
                    metadata: [
                        "noteId": noteID,
                        "bodyBytes": String(displayBody.utf8.count),
                    ]
                )
            case .conflict(let remoteBody):
                conflict = ConflictBanner(remoteBody: remoteBody)
                Log.warning(
                    "Note conflict detected",
                    category: .sync,
                    metadata: [
                        "noteId": noteID,
                        "remoteBytes": String(remoteBody.utf8.count),
                    ]
                )
            }
        } catch {
            // Transient script failures are ignored; the next poll retries.
            Log.warning("Note poll failed (will retry)", category: .sync, metadata: ["noteId": noteID])
        }
    }

    // MARK: - Conflict resolution

    func resolveConflictKeepMine() {
        guard conflict != nil, selectedNoteID != nil else { return }
        Log.info("Conflict resolved: keep mine", category: .sync, metadata: ["noteId": selectedNoteID ?? ""])
        sync.resolveKeepingLocal(localBody: draftBody)
        conflict = nil
        Task { await saveNoteNow(force: true) }
    }

    func resolveConflictTakeRemote() {
        guard let banner = conflict else { return }
        Log.info("Conflict resolved: take theirs", category: .sync, metadata: ["noteId": selectedNoteID ?? ""])
        let displayBody = NoteBodyClassifier.displayText(banner.remoteBody)
        draftBody = displayBody
        sync.resolveTakingRemote(body: displayBody)
        noteIsReadOnly = !NoteBodyClassifier.isEditableAsPlainText(banner.remoteBody)
        conflict = nil
        lastSavedAt = Date()
    }

    // MARK: - Search

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            await loadFoldersAndNotes()
            return
        }
        do {
            searchResults = try await notes.searchNotes(query: query)
            Log.info(
                "Note search completed",
                category: .notes,
                metadata: [
                    "queryLength": String(query.count),
                    "results": String(searchResults.count),
                ]
            )
        } catch {
            // Search failures are non-fatal.
            Log.warning("Note search failed", category: .notes, metadata: ["queryLength": String(query.count)])
        }
    }

    // MARK: - Reminders

    func selectReminderList(_ name: String?) {
        guard selectedListName != name else { return }
        selectedListName = name
        reminderItems = []
        selectedReminderID = nil
        guard let name else { return }
        Task { await loadReminders(listName: name) }
    }

    func loadReminders(listName: String) async {
        do {
            reminderItems = try await reminders.fetchReminders(listName: listName)
            Log.info(
                "Reminders loaded",
                category: .reminders,
                metadata: [
                    "listId": Log.digest(listName),
                    "count": String(reminderItems.count),
                ]
            )
        } catch {
            handleServiceError(error)
        }
    }

    func toggleReminder(_ item: ReminderItem) {
        guard let index = reminderItems.firstIndex(where: { $0.id == item.id }) else { return }
        let completed = !item.isCompleted
        reminderItems[index] = ReminderItem(
            id: item.id,
            name: item.name,
            isCompleted: completed,
            dueEpoch: item.dueEpoch,
            priority: item.priority
        )
        Log.info(
            "Reminder completion toggled",
            category: .reminders,
            metadata: [
                "reminderId": item.id,
                "completed": String(completed),
            ]
        )
        Task {
            do {
                try await reminders.updateReminder(
                    id: item.id,
                    title: nil,
                    isCompleted: completed,
                    dueEpoch: nil,
                    priority: nil,
                    clearDueDate: false
                )
            } catch {
                handleServiceError(error)
                if let selectedListName {
                    await loadReminders(listName: selectedListName)
                }
            }
        }
    }

    func quickCapture() {
        let text = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let listName = selectedListName else { return }
        quickCaptureText = ""
        Log.info("Reminder quick capture", category: .reminders, metadata: ["listId": Log.digest(listName)])
        Task {
            do {
                let created = try await reminders.createReminder(title: text, listName: listName)
                reminderItems.insert(created, at: 0)
            } catch {
                handleServiceError(error)
                Log.error(
                    "Reminder quick capture failed",
                    category: .reminders,
                    metadata: ["listId": Log.digest(listName)]
                )
            }
        }
    }

    func updateReminderName(_ item: ReminderItem, to newName: String) {
        guard let index = reminderItems.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        reminderItems[index] = ReminderItem(
            id: item.id,
            name: trimmed.isEmpty ? item.name : trimmed,
            isCompleted: item.isCompleted,
            dueEpoch: item.dueEpoch,
            priority: item.priority
        )
        guard !trimmed.isEmpty else { return }
        Log.info("Reminder renamed", category: .reminders, metadata: ["reminderId": item.id])
        Task {
            do {
                try await reminders.updateReminder(
                    id: item.id,
                    title: trimmed,
                    isCompleted: nil,
                    dueEpoch: nil,
                    priority: nil,
                    clearDueDate: false
                )
            } catch {
                handleServiceError(error)
            }
        }
    }

    func updateReminderDetails(_ item: ReminderItem, dueEpoch: TimeInterval?, priority: Int) {
        guard let index = reminderItems.firstIndex(where: { $0.id == item.id }) else { return }
        reminderItems[index] = ReminderItem(
            id: item.id,
            name: item.name,
            isCompleted: item.isCompleted,
            dueEpoch: dueEpoch,
            priority: priority
        )
        Log.info(
            "Reminder details updated",
            category: .reminders,
            metadata: [
                "reminderId": item.id,
                "priority": String(priority),
            ]
        )
        Task {
            do {
                try await reminders.updateReminder(
                    id: item.id,
                    title: nil,
                    isCompleted: nil,
                    dueEpoch: dueEpoch,
                    priority: priority,
                    clearDueDate: false
                )
            } catch {
                handleServiceError(error)
            }
        }
    }

    func clearReminderDueDate(_ item: ReminderItem) {
        guard let index = reminderItems.firstIndex(where: { $0.id == item.id }) else { return }
        reminderItems[index] = ReminderItem(
            id: item.id,
            name: item.name,
            isCompleted: item.isCompleted,
            dueEpoch: nil,
            priority: item.priority
        )
        Log.info("Reminder due date cleared", category: .reminders, metadata: ["reminderId": item.id])
        Task {
            do {
                try await reminders.updateReminder(
                    id: item.id,
                    title: nil,
                    isCompleted: nil,
                    dueEpoch: nil,
                    priority: nil,
                    clearDueDate: true
                )
            } catch {
                handleServiceError(error)
            }
        }
    }

    func deleteReminder(_ item: ReminderItem) {
        reminderItems.removeAll { $0.id == item.id }
        Log.info("Reminder deleted", category: .reminders, metadata: ["reminderId": item.id])
        Task {
            do {
                try await reminders.deleteReminder(id: item.id)
            } catch {
                handleServiceError(error)
            }
        }
    }

    // MARK: - Panel control

    func hidePanel() {
        coordinator?.hidePanel()
    }

    // MARK: - Error handling

    private func handleServiceError(_ error: Error) {
        if let scriptError = error as? ScriptError {
            // Log only the classified kind, never the raw AppleScript message,
            // which can echo back user content.
            let kind: String
            switch scriptError {
            case .permissionDenied:
                kind = "permissionDenied"
                automationDenied = true
                automationNeedsAppLaunch = false
                automationError = scriptError.errorDescription
                statusMessage = nil
            case .appNotRunning:
                kind = "appNotRunning"
                automationNeedsAppLaunch = true
                automationError = scriptError.errorDescription
            case .timedOut:
                kind = "timedOut"
                automationError = scriptError.errorDescription
            case .executionFailed:
                kind = "executionFailed"
                automationError = scriptError.errorDescription
                statusMessage = scriptError.errorDescription
            case .malformedOutput:
                kind = "malformedOutput"
                automationError = scriptError.errorDescription
                statusMessage = scriptError.errorDescription
            }
            Log.error("Automation service error", category: .bridge, metadata: ["kind": kind])
        } else {
            statusMessage = error.localizedDescription
            Log.error("Automation service error", category: .bridge, metadata: ["kind": "unknown"])
        }
    }
}
