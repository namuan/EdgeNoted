import Observation

@Observable
final class AppState {
    var isLoading: Bool = false
    var selectedItemID: Item.ID?
}
