import AppKit
import SwiftUI

/// Owns the main edge panel: placement, slide animations, show/hide.
@MainActor
final class EdgePanelController: NSObject {
    private let appState: AppState
    private let settings: SettingsStore
    let panel: EdgePanel

    init(appState: AppState, settings: SettingsStore) {
        self.appState = appState
        self.settings = settings

        let panelSize = settings.panelSize
        panel = EdgePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        let rootView = PanelRootView()
            .environment(appState)
            .environment(settings)
            .modelContainer(PersistenceController.container)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    func show(animated: Bool = true) {
        guard !panel.isVisible else { return }
        let screen = Self.screenForPresentation()
        let frame = ScreenEdgeGeometry.visibleFrame(
            screen: screen.visibleFrame,
            edge: settings.hotSideEdge,
            panelSize: settings.panelSize,
            margin: settings.panelMargin
        )
        Log.info(
            "Edge panel showing",
            category: .windowing,
            metadata: [
                "edge": settings.hotSideEdge.rawValue,
                "screen": screen.localizedName,
                "frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))",
            ]
        )
        let hiddenFrame = ScreenEdgeGeometry.hiddenFrame(visible: frame, edge: settings.hotSideEdge)
        panel.setFrame(hiddenFrame, display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        appState.isPanelVisible = true

        guard animated else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.makeKey()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.makeKey()
            }
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        appState.isPanelVisible = false
        Log.info(
            "Edge panel hiding",
            category: .windowing,
            metadata: [
                "edge": settings.hotSideEdge.rawValue
            ]
        )
        let hiddenFrame = ScreenEdgeGeometry.hiddenFrame(visible: panel.frame, edge: settings.hotSideEdge)

        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
            }
        }
    }

    /// Applies a changed panel size from settings.
    func updatePanelSize() {
        let size = settings.panelSize
        panel.setContentSize(size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        if panel.isVisible {
            let screen = Self.screenForPresentation()
            panel.setFrame(
                ScreenEdgeGeometry.visibleFrame(
                    screen: screen.visibleFrame,
                    edge: settings.hotSideEdge,
                    panelSize: size,
                    margin: settings.panelMargin
                ),
                display: true
            )
        }
    }

    /// The screen to present on: the one containing the pointer if any,
    /// otherwise the main screen.
    private static func screenForPresentation() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}
