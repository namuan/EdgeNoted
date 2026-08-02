import AppKit

/// Owns the floating panel, open bar, global hotkey, and hot-side monitor, and
/// wires them to AppState.
@MainActor
final class ApplicationCoordinator {
    private let appState: AppState
    private let settings: SettingsStore
    private let panelController: EdgePanelController
    private let hotKeyController: GlobalHotKeyController
    private var openBarController: OpenBarController?
    private var hotSideMonitor: HotSideMonitor?
    private var didStart = false

    init(appState: AppState, settings: SettingsStore) {
        self.appState = appState
        self.settings = settings
        self.panelController = EdgePanelController(appState: appState, settings: settings)
        self.hotKeyController = GlobalHotKeyController()
        self.openBarController = nil
        self.hotSideMonitor = nil
        // Self is fully initialized now; closures may capture it.
        self.openBarController = OpenBarController(settings: settings) { [weak self] in
            self?.togglePanel()
        }
        self.hotSideMonitor = HotSideMonitor(
            settings: settings,
            onShow: { [weak self] in self?.showPanel() },
            onAutoHide: { [weak self] in self?.hidePanel() },
            isPanelVisible: { [weak self] in self?.appState.isPanelVisible ?? false },
            panelFrameProvider: { [weak self] in self?.panelController.panel.frame ?? .zero },
            openBarFrameProvider: { [weak self] in self?.openBarController?.frame ?? .zero }
        )
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        appState.coordinator = self
        registerHotKey()
        hotSideMonitor?.start()
        openBarController?.show()
        Log.info(
            "Panel services started",
            category: .windowing,
            metadata: [
                "edge": settings.hotSideEdge.rawValue,
                "hotSide": String(settings.hotSideEnabled),
                "hotKey": settings.hotKeyDescription,
            ]
        )
    }

    func stop() {
        hotKeyController.unregister()
        hotSideMonitor?.stop()
        Log.info("Panel services stopped", category: .windowing)
    }

    // MARK: - Panel visibility

    func showPanel() {
        Log.info(
            "Panel show",
            category: .windowing,
            metadata: [
                "edge": settings.hotSideEdge.rawValue,
                "screen": NSScreen.main?.localizedName ?? "unknown",
            ]
        )
        panelController.show()
        // First show triggers the initial load, so the Notes/Reminders
        // permission prompt appears in context (just in time), never at launch.
        Task { await appState.ensureStarted() }
    }

    func hidePanel() {
        Log.info("Panel hide", category: .windowing)
        Task { await appState.flushPendingSave() }
        panelController.hide()
    }

    func togglePanel() {
        let wasVisible = panelController.isVisible
        Log.info("Panel toggle", category: .windowing, metadata: ["visible": String(wasVisible)])
        if wasVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func openSettings() {
        Log.info("Settings requested", category: .settings)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Settings-driven updates

    func applySettings() {
        registerHotKey()
        hotSideMonitor?.start()
        openBarController?.updateEdge()
        panelController.updatePanelSize()
        Log.info(
            "Settings applied",
            category: .settings,
            metadata: [
                "edge": settings.hotSideEdge.rawValue,
                "hotSide": String(settings.hotSideEnabled),
                "hotKey": settings.hotKeyDescription,
                "panel": "\(Int(settings.panelWidth))x\(Int(settings.panelHeight))",
                "pollInterval": String(settings.pollInterval),
            ]
        )
    }

    private func registerHotKey() {
        Log.info(
            "Registering global hotkey",
            category: .windowing,
            metadata: [
                "keyCode": String(settings.hotKeyCode),
                "shortcut": settings.hotKeyDescription,
            ]
        )
        hotKeyController.register(
            keyCode: UInt32(settings.hotKeyCode),
            modifiers: settings.carbonModifiers
        ) { [weak self] in
            self?.togglePanel()
        }
    }
}
