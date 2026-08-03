import Foundation
import Testing

@testable import EdgeNoted

/// End-to-end AppState logic driven through the fake services and an
/// in-memory SwiftData store. Never touches Apple Notes or Reminders.
@Suite("AppState integration with fake services")
@MainActor
struct AppStateIntegrationTests {
    private enum TestError: Error {
        case noDefaults
    }

    private struct Harness {
        let state: AppState
        let notes: FakeNotesService
    }

    private func makeHarness() async throws -> Harness {
        let notes = FakeNotesService()
        await notes.seed(id: "n1", name: "Meeting", body: "Discuss roadmap", folderName: "Work")
        let reminders = FakeRemindersService()
        let container = try PersistenceController.inMemoryContainer()
        let suiteName = "AppStateIntegrationTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.noDefaults
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)
        // The harness displays "n1" as the single configured note, as picked
        // in Settings.
        settings.configuredNoteID = "n1"
        settings.configuredNoteFolderName = "Work"
        settings.configuredNoteName = "Meeting"
        let state = AppState(notes: notes, reminders: reminders, settings: settings, modelContainer: container)
        return Harness(state: state, notes: notes)
    }

    @Test("Startup loads folders and reminder lists")
    func startup() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        #expect(harness.state.folders.count == 2)
        #expect(harness.state.reminderLists.count == 2)
    }

    @Test("Startup loads the single configured note into the editor")
    func startupLoadsConfiguredNote() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        #expect(harness.state.selectedNoteID == "n1")
        #expect(harness.state.selectedFolderName == "Work")
        #expect(harness.state.draftTitle == "Meeting")
        #expect(harness.state.draftBody == "Discuss roadmap")
    }

    @Test("Startup with no configured note leaves the editor empty")
    func startupWithNoConfiguredNote() async throws {
        let harness = try await makeHarness()
        harness.state.settings.configuredNoteID = nil
        harness.state.settings.configuredNoteFolderName = nil
        harness.state.settings.configuredNoteName = nil
        await harness.state.startup()
        #expect(harness.state.selectedNoteID == nil)
        #expect(harness.state.draftBody.isEmpty)
        #expect(harness.state.draftTitle.isEmpty)
    }

    @Test("Reconfiguring the displayed note reloads it")
    func reconfiguringNoteReloads() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        await harness.notes.seed(id: "n2", name: "Second", body: "Other body", folderName: "Work")
        harness.state.settings.configuredNoteID = "n2"
        harness.state.settings.configuredNoteFolderName = "Work"
        harness.state.settings.configuredNoteName = "Second"
        await harness.state.loadConfiguredNote()
        #expect(harness.state.selectedNoteID == "n2")
        #expect(harness.state.draftBody == "Other body")
        #expect(harness.state.selectedFolderName == "Work")
    }

    @Test("ensureStarted loads services exactly once")
    func ensureStartedIsIdempotent() async throws {
        let harness = try await makeHarness()
        await harness.state.ensureStarted()
        let fetchCountAfterFirst = await harness.notes.folderFetchCount
        await harness.state.ensureStarted()
        #expect(harness.state.folders.count == 2)
        // A second call must not trigger another load pass.
        #expect(await harness.notes.folderFetchCount == fetchCountAfterFirst)
    }

    @Test("Selecting a note loads its body into the draft")
    func selectNote() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        #expect(harness.state.selectedNoteID == "n1")
        #expect(harness.state.draftBody == "Discuss roadmap")
        #expect(!harness.state.noteIsReadOnly)
    }

    @Test("Local note metadata stores the folder ID, never the folder name")
    func metadataStoresFolderID() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        await waitForNoteOpen(harness.state)
        let context = harness.state.modelContainer.mainContext
        let meta = MetaStore.noteMeta(createIfNeededFor: "n1", folderID: "f-work", in: context)
        #expect(meta.folderID == "f-work")  // real ID, not the "Work" name
        #expect(meta.folderID != "Work")
    }

    @Test("Editing then saving writes back to the fake service")
    func editAndSave() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        harness.state.draftBody = "Updated body"
        harness.state.bodyChanged()
        await harness.state.flushPendingSave()
        let detail = try await harness.notes.fetchNote(id: "n1")
        #expect(detail.body == "Updated body")
        #expect(harness.state.lastSavedAt != nil)
    }

    @Test("External edits are adopted when the draft is clean")
    func externalEditAdopted() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        await harness.notes.simulateExternalEdit(id: "n1", name: "Meeting (updated)", body: "New agenda")
        await harness.state.pollSelectedNote()
        #expect(harness.state.draftBody == "New agenda")
        #expect(harness.state.conflict == nil)
    }

    @Test("External edits while editing raise a conflict, not data loss")
    func conflictDetected() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        harness.state.draftBody = "My local changes"
        harness.state.bodyChanged()
        await harness.notes.simulateExternalEdit(id: "n1", name: "Meeting", body: "Their changes")
        await harness.state.pollSelectedNote()
        #expect(harness.state.conflict != nil)
        // Keep mine wins and pushes local over remote.
        harness.state.resolveConflictKeepMine()
        await harness.state.flushPendingSave()
        let detail = try await harness.notes.fetchNote(id: "n1")
        #expect(detail.body == "My local changes")
        #expect(harness.state.conflict == nil)
    }

    @Test("Switching notes before the debounce fires saves the old note")
    func pendingSaveSurvivesSwitch() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        await harness.notes.seed(id: "n2", name: "Second", body: "Other body", folderName: "Work")
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        harness.state.draftBody = "Edit that must survive"
        harness.state.bodyChanged()
        // Switch before the 1.2s debounce can fire.
        harness.state.selectNote("n2")
        await waitForNoteOpen(harness.state)
        await harness.state.flushPendingSave()
        let first = try await harness.notes.fetchNote(id: "n1")
        #expect(first.body == "Edit that must survive")
        // The second note must not have been touched.
        let second = try await harness.notes.fetchNote(id: "n2")
        #expect(second.body == "Other body")
    }

    @Test("Hiding without edits never writes the note back")
    func hideWithoutEditsDoesNotWrite() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        let before = try await harness.notes.fetchNote(id: "n1")
        await harness.state.flushPendingSave()
        let after = try await harness.notes.fetchNote(id: "n1")
        #expect(after.body == "Discuss roadmap")
        // The modification epoch is unchanged, proving no write occurred.
        #expect(after.modificationEpoch == before.modificationEpoch)
    }

    @Test("A note that failed to load is never wiped on hide")
    func failedLoadIsNotWiped() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("does-not-exist")
        for _ in 0..<100 {
            await Task.yield()
        }
        // Draft could not be loaded; hiding must not force-write it.
        await harness.state.flushPendingSave()
        let all = try await harness.notes.fetchNotes(folderName: nil)
        #expect(all.count == 1)
        let existing = try await harness.notes.fetchNote(id: "n1")
        #expect(existing.body == "Discuss roadmap")
    }

    @Test("Remote title-only edits are adopted on a clean draft")
    func titleOnlyEditAdopted() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectNote("n1")
        await waitForNoteOpen(harness.state)
        await harness.notes.simulateExternalEdit(id: "n1", name: "Renamed in Notes", body: "Discuss roadmap")
        await harness.state.pollSelectedNote()
        #expect(harness.state.draftTitle == "Renamed in Notes")
        #expect(harness.state.draftBody == "Discuss roadmap")
    }

    /// Waits until the async open of the seeded note has populated the draft.
    private func waitForNoteOpen(_ state: AppState) async {
        for _ in 0..<2_000 {
            if state.draftBody == "Discuss roadmap" {
                return
            }
            await Task.yield()
        }
    }

    @Test("Reminder quick capture creates an item in the selected list")
    func quickCapture() async throws {
        let harness = try await makeHarness()
        await harness.state.startup()
        harness.state.selectedListName = "Work"
        harness.state.quickCaptureText = "Ship the panel"
        harness.state.quickCapture()
        #expect(harness.state.quickCaptureText.isEmpty)
        for _ in 0..<2_000 {
            if harness.state.reminderItems.contains(where: { $0.name == "Ship the panel" }) {
                break
            }
            await Task.yield()
        }
        #expect(harness.state.reminderItems.contains { $0.name == "Ship the panel" })
    }

    @Test("Clearing a reminder due date removes it through the bridge contract")
    func clearReminderDueDate() async throws {
        let reminders = FakeRemindersService()
        await reminders.seed(name: "Task", listName: "Work")
        let items = try await reminders.fetchReminders(listName: "Work")
        let item = try #require(items.first)
        try await reminders.updateReminder(
            id: item.id,
            title: nil,
            isCompleted: nil,
            dueEpoch: 1_700_000_000,
            priority: nil
        )
        let withDue = try await reminders.fetchReminders(listName: "Work")
        #expect(withDue.first?.dueEpoch == 1_700_000_000)
        try await reminders.updateReminder(
            id: item.id,
            title: nil,
            isCompleted: nil,
            dueEpoch: nil,
            priority: nil,
            clearDueDate: true
        )
        let cleared = try await reminders.fetchReminders(listName: "Work")
        #expect(cleared.first?.dueEpoch == nil)
    }
}
