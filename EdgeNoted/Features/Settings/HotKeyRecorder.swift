import AppKit

/// Captures the next key press (with at least one modifier) so the user can
/// record a global shortcut. Uses a local event monitor, which only receives
/// events while the settings window is active.
@MainActor
final class HotKeyRecorder {
    private var monitor: Any?

    func begin(capture: @escaping (_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> Void) {
        end()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return event }
            self.end()
            capture(Int(event.keyCode), flags)
            return nil
        }
    }

    func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
