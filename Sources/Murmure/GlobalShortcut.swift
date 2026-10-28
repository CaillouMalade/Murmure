import AppKit
import Carbon
import MurmureCore

private func murmureHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let data else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard result == noErr, identifier.signature == 0x4D75726D else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalShortcut>.fromOpaque(data).takeUnretainedValue()
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    Task { @MainActor in monitor.changed?(pressed) }
    return noErr
}

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var changed: ((Bool) -> Void)?
    func unregister() { if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil }
    func register(_ shortcut: KeyboardShortcut, enabled: Bool) throws {
        unregister(); guard enabled else { return }
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), murmureHotKeyHandler, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw MurmureError.message("The dictation shortcut listener could not start (\(status)).") }
        }
        var modifiers: UInt32 = 0
        if shortcut.control { modifiers |= UInt32(controlKey) }; if shortcut.option { modifiers |= UInt32(optionKey) }
        if shortcut.command { modifiers |= UInt32(cmdKey) }; if shortcut.shift { modifiers |= UInt32(shiftKey) }
        let status = RegisterEventHotKey(shortcut.keyCode, modifiers, EventHotKeyID(signature: 0x4D75726D, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { throw MurmureError.message("That shortcut is unavailable (\(status)). Choose another combination in Settings.") }
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class ShortcutRecorder: NSButton {
    var value = KeyboardShortcut() { didSet { title = value.display } }
    var captureChanged: ((Bool) -> Void)?
    private var capturing = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); capturing = true; captureChanged?(true); title = "Press shortcut… (Esc cancels)"
    }
    override func keyDown(with event: NSEvent) {
        guard capturing else { super.keyDown(with: event); return }
        if event.keyCode != 53 {
            let flags = event.modifierFlags
            guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { NSSound.beep(); return }
            var shortcut = KeyboardShortcut(); shortcut.keyCode = UInt32(event.keyCode)
            shortcut.control = flags.contains(.control); shortcut.option = flags.contains(.option); shortcut.command = flags.contains(.command); shortcut.shift = flags.contains(.shift)
            let labels: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            shortcut.keyLabel = labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            value = shortcut
        }
        capturing = false; title = value.display; captureChanged?(false); window?.makeFirstResponder(nil)
    }
    override func resignFirstResponder() -> Bool {
        if capturing { capturing = false; title = value.display; captureChanged?(false) }
        return super.resignFirstResponder()
    }
}
