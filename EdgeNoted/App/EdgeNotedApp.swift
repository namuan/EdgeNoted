import SwiftUI

@main
struct EdgeNotedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
                .environment(appDelegate.settings)
        }
    }
}

/// Builds the app services, decides between the live AppleScript bridge and
/// the fake services (used by UI tests), and starts the panel coordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private(set) var appState: AppState!
    private var coordinator: ApplicationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let useFakes = UserDefaults.standard.bool(forKey: "UITestFakeServices")
        Log.info(
            "Application did finish launching",
            category: .lifecycle,
            metadata: [
                "services": useFakes ? "fake" : "eventkit",
                "version": "1.6",
            ]
        )

        let notes: any NotesService
        let reminders: any RemindersService

        if useFakes {
            let fakeNotes = FakeNotesService(seed: [
                FakeNotesService.Seed(
                    id: "seed-1",
                    name: "Welcome to EdgeNoted",
                    body: "Edit this note - changes sync to Apple Notes.",
                    folderName: nil
                ),
                FakeNotesService.Seed(
                    id: "seed-2",
                    name: "Shopping",
                    body: "- [ ] Milk\n- [x] Coffee\n- [ ] #E5484D hex colors render as swatches",
                    folderName: nil
                ),
            ])
            let fakeReminders = FakeRemindersService(seed: [
                FakeRemindersService.Seed(name: "Call the dentist", listName: "Home", isCompleted: false),
                FakeRemindersService.Seed(name: "File expenses", listName: "Work", isCompleted: false),
            ])
            notes = fakeNotes
            reminders = fakeReminders
        } else {
            notes = AppleScriptNotesService()
            reminders = EventKitRemindersService()
        }

        let appState = AppState(notes: notes, reminders: reminders, settings: settings)
        self.appState = appState
        let coordinator = ApplicationCoordinator(appState: appState, settings: settings)
        self.coordinator = coordinator
        coordinator.start()
        Log.info("Coordinator started", category: .lifecycle)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("Application will terminate", category: .lifecycle)
        coordinator?.stop()
        // Flush buffered lines and close the handle. closeSynchronously runs
        // off the main actor so termination never deadlocks on it.
        Log.closeSynchronously()
    }
}
