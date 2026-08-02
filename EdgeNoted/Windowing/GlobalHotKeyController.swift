import Carbon.HIToolbox

/// Global keyboard shortcut via Carbon's RegisterEventHotKey, which works
/// without accessibility permission.
@MainActor
final class GlobalHotKeyController {
    private static let signature: OSType = 0x4544_4E47  // "EDNG"

    /// Invoked on the main actor when the shortcut is pressed.
    /// `nonisolated(unsafe)` is required because Carbon callbacks are C
    /// function pointers that carry no actor isolation; the value is only ever
    /// touched on the main actor.
    nonisolated(unsafe) private static var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) {
        unregister()
        Self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamName(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, hotKeyID.signature == GlobalHotKeyController.signature {
                    Task { @MainActor in
                        GlobalHotKeyController.onPress?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status == noErr {
            Log.info(
                "Global hotkey registered",
                category: .windowing,
                metadata: [
                    "keyCode": String(keyCode),
                    "modifiers": String(modifiers),
                ]
            )
        } else {
            Log.warning(
                "Global hotkey registration failed",
                category: .windowing,
                metadata: [
                    "status": String(status)
                ]
            )
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            Log.info("Global hotkey unregistered", category: .windowing)
        }
        hotKeyRef = nil
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
    }
}
