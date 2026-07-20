import Carbon

/// Регистрирует глобальный undo-хоткей через Carbon (`RegisterEventHotKey`).
/// По умолчанию: Control+Option+U ("U" — undo). Комбо перехватывается системно.
final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Вызывается при нажатии хоткея.
    var onTrigger: (() -> Void)?

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData!).takeUnretainedValue()
                controller.onTrigger?()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x50535748), id: 1) // 'PSWH'
        let modifiers = UInt32(controlKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_U)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
