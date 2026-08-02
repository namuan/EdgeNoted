import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 420, height: 240)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var appState: AppState
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Text("General settings go here.")
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            Toggle("Show loading state", isOn: $appState.isLoading)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
