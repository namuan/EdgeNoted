import AppKit
import SwiftUI

/// A thin, always-on-top strip at the chosen screen edge. Clicking it toggles
/// the main panel ("Open Bar" invocation).
@MainActor
final class OpenBarController: NSObject {
    private let settings: SettingsStore
    private let panel: NSPanel
    private let hosting: NSHostingView<OpenBarView>

    init(settings: SettingsStore, onToggle: @escaping () -> Void) {
        self.settings = settings
        let barSize = Self.barSize(for: settings.hotSideEdge)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: barSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: OpenBarView(onToggle: onToggle))
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false

        hosting.frame = NSRect(origin: .zero, size: barSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = ScreenEdgeGeometry.barFrame(
            screen: screen.frame,
            edge: settings.hotSideEdge,
            barSize: Self.barSize(for: settings.hotSideEdge)
        )
        panel.setFrame(frame, display: false)
        panel.orderFront(nil)
    }

    /// Frame used by the hot-side monitor to avoid auto-hiding while the
    /// pointer hovers over the bar.
    var frame: NSRect { panel.frame }

    /// Repositions the bar after the edge setting changes.
    func updateEdge() {
        let barSize = Self.barSize(for: settings.hotSideEdge)
        panel.setContentSize(barSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: barSize)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(
            ScreenEdgeGeometry.barFrame(screen: screen.frame, edge: settings.hotSideEdge, barSize: barSize),
            display: false
        )
    }

    private static func barSize(for edge: ScreenEdge) -> NSSize {
        switch edge {
        case .left, .right: NSSize(width: 8, height: 110)
        case .bottom: NSSize(width: 110, height: 8)
        }
    }
}

/// The strip content: a subtle rounded bar that reacts to clicks.
private struct OpenBarView: View {
    let onToggle: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.16))
            .frame(width: 3, height: 90)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
            .accessibilityLabel("EdgeNoted Open Bar")
            .help("Click to show EdgeNoted")
    }
}
