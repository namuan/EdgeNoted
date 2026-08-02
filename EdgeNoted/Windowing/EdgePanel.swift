import AppKit

/// The borderless, always-on-top panel that hosts the EdgeNoted surface.
///
/// It is a non-activating panel so EdgeNoted never steals focus from the
/// user's current app, but it still accepts key status so text editing works.
final class EdgePanel: NSPanel {
    override nonisolated var canBecomeKey: Bool { true }
}
