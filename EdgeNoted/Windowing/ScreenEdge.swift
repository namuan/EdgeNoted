import CoreGraphics

/// The screen edge the panel slides in from.
enum ScreenEdge: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
        }
    }
}

/// Pure geometry helpers for edge detection and panel placement.
///
/// Screen frames are expected in Cocoa global coordinates (origin at the
/// bottom-left of the primary display), which matches `NSScreen.frame` and
/// `NSEvent.mouseLocation`.
enum ScreenEdgeGeometry {
    /// Returns the edge the given point is touching, if any. Corners are
    /// excluded so the pointer never triggers two edges at once. When a point
    /// sits on the shared boundary of two screens, the screen that actually
    /// contains the point wins.
    static func edge(containing point: CGPoint, screens: [CGRect], threshold: CGFloat) -> ScreenEdge? {
        // Check the screen whose interior contains the point first so
        // multi-display boundaries are deterministic.
        if let containing = screens.first(where: { $0.contains(point) }),
            let edge = edgeOfScreen(containing, point: point, threshold: threshold)
        {
            return edge
        }
        for screen in screens {
            if let edge = edgeOfScreen(screen, point: point, threshold: threshold) {
                return edge
            }
        }
        return nil
    }

    private static func edgeOfScreen(_ screen: CGRect, point: CGPoint, threshold: CGFloat) -> ScreenEdge? {
        let cornerMargin = threshold * 5
        if point.x <= screen.minX + threshold,
            point.y > screen.minY + cornerMargin,
            point.y < screen.maxY - cornerMargin
        {
            return .left
        }
        if point.x >= screen.maxX - threshold,
            point.y > screen.minY + cornerMargin,
            point.y < screen.maxY - cornerMargin
        {
            return .right
        }
        if point.y <= screen.minY + threshold,
            point.x > screen.minX + cornerMargin,
            point.x < screen.maxX - cornerMargin
        {
            return .bottom
        }
        return nil
    }

    /// True when the point is within `threshold` of any edge of any screen.
    /// Used to decide when the hot-side trigger can be re-armed.
    static func isNearAnyEdge(point: CGPoint, screens: [CGRect], threshold: CGFloat) -> Bool {
        for screen in screens {
            if point.x <= screen.minX + threshold
                || point.x >= screen.maxX - threshold
                || point.y <= screen.minY + threshold
                || point.y >= screen.maxY - threshold
            {
                return true
            }
        }
        return false
    }

    /// Frame for the panel when visible, docked at `edge` of the usable screen
    /// area. Callers provide `NSScreen.visibleFrame` so the panel avoids system
    /// UI such as the menu bar and Dock.
    static func visibleFrame(screen: CGRect, edge: ScreenEdge, panelSize: CGSize, margin: CGFloat) -> CGRect {
        switch edge {
        case .left:
            return CGRect(
                x: screen.minX + margin,
                y: screen.minY,
                width: panelSize.width,
                height: screen.height
            )
        case .right:
            return CGRect(
                x: screen.maxX - panelSize.width - margin,
                y: screen.minY,
                width: panelSize.width,
                height: screen.height
            )
        case .bottom:
            return CGRect(
                x: screen.midX - panelSize.width / 2,
                y: screen.minY,
                width: panelSize.width,
                height: screen.height
            )
        }
    }

    /// Frame just off-screen at `edge`, used as the start/end of slide
    /// animations so the panel visibly comes from the screen edge.
    static func hiddenFrame(visible: CGRect, edge: ScreenEdge) -> CGRect {
        switch edge {
        case .left:
            return visible.offsetBy(dx: -visible.width - 32, dy: 0)
        case .right:
            return visible.offsetBy(dx: visible.width + 32, dy: 0)
        case .bottom:
            return visible.offsetBy(dx: 0, dy: -visible.height - 32)
        }
    }

    /// Frame for the open-bar strip at `edge`.
    static func barFrame(screen: CGRect, edge: ScreenEdge, barSize: CGSize) -> CGRect {
        switch edge {
        case .left:
            return CGRect(
                x: screen.minX,
                y: screen.midY - barSize.height / 2,
                width: barSize.width,
                height: barSize.height
            )
        case .right:
            return CGRect(
                x: screen.maxX - barSize.width,
                y: screen.midY - barSize.height / 2,
                width: barSize.width,
                height: barSize.height
            )
        case .bottom:
            return CGRect(
                x: screen.midX - barSize.width / 2,
                y: screen.minY,
                width: barSize.width,
                height: barSize.height
            )
        }
    }
}
