import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [Item] = []

    var body: some View {
        NavigationSplitView {
            List(items, selection: Bindable(appState).selectedItemID) { item in
                Text(item.name)
                    .tag(item.id)
            }
            .navigationTitle("Items")
        } detail: {
            if let selected = items.first(where: { $0.id == appState.selectedItemID }) {
                Text(selected.name)
                    .font(.title)
                    .padding()
            } else {
                ContentUnavailableView("Select an item", systemImage: "sidebar.left")
            }
        }
        .tint(AppColor.accent)
        .background(AppColor.background)
        .overlay {
            if appState.isLoading {
                ProgressView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
