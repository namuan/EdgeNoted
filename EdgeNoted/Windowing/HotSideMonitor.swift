import AppKit
import Foundation

/// Watches the pointer and shows/hides the panel when it hugs the chosen
/// screen edge (Hot Side mode).
///
/// Polling `NSEvent.mouseLocation` avoids requiring accessibility permission
/// and works across displays. The timer uses target/selector instead of a
/// closure so no @Sendable captures are involved.
@MainActor
final class HotSideMonitor {
    private let settings: SettingsStore
    private let onShow: () -> Void
    private let onAutoHide: () -> Void
    private let isPanelVisible: () -> Bool
    private let panelFrameProvider: () -> CGRect
    private let openBarFrameProvider: () -> CGRect

    private var timer: Timer?
    private var armed = true
    private var enteredAt: CFTimeInterval?
    private var leftAt: CFTimeInterval?
    private let tickInterval: TimeInterval = 0.06

    init(
        settings: SettingsStore,
        onShow: @escaping () -> Void,
        onAutoHide: @escaping () -> Void,
        isPanelVisible: @escaping () -> Bool,
        panelFrameProvider: @escaping () -> CGRect,
        openBarFrameProvider: @escaping () -> CGRect
    ) {
        self.settings = settings
        self.onShow = onShow
        self.onAutoHide = onAutoHide
        self.isPanelVisible = isPanelVisible
        self.panelFrameProvider = panelFrameProvider
        self.openBarFrameProvider = openBarFrameProvider
    }

    func start() {
        stop()
        let timer = Timer(
            timeInterval: tickInterval,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        guard settings.hotSideEnabled else { return }
        let pointer = NSEvent.mouseLocation
        if isPanelVisible() {
            autoHideIfOutside(pointer: pointer)
        } else {
            showIfAtEdge(pointer: pointer)
        }
    }

    private func autoHideIfOutside(pointer: CGPoint) {
        let inPanel = panelFrameProvider().contains(pointer)
        let inBar = openBarFrameProvider().contains(pointer)
        if inPanel || inBar {
            leftAt = nil
            return
        }
        let now = CACurrentMediaTime()
        if leftAt == nil {
            leftAt = now
        } else if now - (leftAt ?? now) > settings.autoHideDelay {
            leftAt = nil
            onAutoHide()
        }
    }

    private func showIfAtEdge(pointer: CGPoint) {
        let screens = NSScreen.screens.map(\.frame)
        let threshold = CGFloat(settings.hotSideThreshold)

        guard let edge = ScreenEdgeGeometry.edge(containing: pointer, screens: screens, threshold: threshold),
            edge == settings.hotSideEdge
        else {
            enteredAt = nil
            if !ScreenEdgeGeometry.isNearAnyEdge(point: pointer, screens: screens, threshold: threshold * 4) {
                armed = true
            }
            return
        }

        guard armed else { return }
        let now = CACurrentMediaTime()
        if enteredAt == nil {
            enteredAt = now
        } else if now - (enteredAt ?? now) > settings.hotSideArmDelay {
            enteredAt = nil
            armed = false
            onShow()
        }
    }
}
