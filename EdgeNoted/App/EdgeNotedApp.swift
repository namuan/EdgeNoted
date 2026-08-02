import SwiftData
import SwiftUI

@main
struct EdgeNotedApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(PersistenceController.container)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
