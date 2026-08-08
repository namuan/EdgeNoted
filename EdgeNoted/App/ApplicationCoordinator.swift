import AppKit
import SwiftUI

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
    /// Manually hosted settings window. The SwiftUI `Settings` scene's
    /// `showSettingsWindow:` action is unreliable from a non-activating panel
    /// in an LSUIElement app, so the coordinator owns a real window instead.
    private var settingsWindow: NSWindow?

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
        // Every subsequent show reloads the selected Reminders list so changes
        // made in Apple Reminders, including newly overdue items, are visible.
        Task {
            await appState.ensureStarted()
            await appState.refreshReminders()
        }
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
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = makeSettingsWindow()
            settingsWindow = window
        }
        // The panel is non-activating, so the app is still inactive when the
        // settings button is clicked. Activate it or the window stays behind.
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds a standard window hosting the SwiftUI SettingsView with the same
    /// environment wiring the panel uses.
    private func makeSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView()
                .environment(appState)
                .environment(settings)
                .modelContainer(PersistenceController.container)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "EdgeNoted Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        return window
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
            ]
        )
    }

    // MARK: - Quit

    /// The only in-app way to exit: EdgeNoted has no Dock icon and no menu bar
    /// icon, so the system's usual quit affordances do not exist. Asks for
    /// confirmation (the panel sits at the screen edge where misclicks are
    /// easy), then flushes unsaved edits and terminates.
    func requestQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit EdgeNoted?"
        alert.informativeText = "Unsaved edits will be written to Apple Notes before quitting."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            quit()
        }
    }

    /// Flushes the debounced note save so edits made in the panel land in
    /// Apple Notes, then terminates the app.
    func quit() {
        Log.info("Quit requested", category: .lifecycle)
        Task { [weak self] in
            guard let self else { return }
            await self.appState.flushPendingSave()
            NSApp.terminate(nil)
        }
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
