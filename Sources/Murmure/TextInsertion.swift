import AppKit
import ApplicationServices
import CryptoKit
import MurmureCore

@MainActor
struct TextInsertionTarget {
    private let element: AXUIElement
    private let pid: pid_t
    private let selection: CFRange
    private let fingerprint: Data?

    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    private static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute as CFString), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
    private static func digest(_ element: AXUIElement) -> Data? {
        guard let value = attribute(element, kAXValueAttribute as CFString) as? String else { return nil }
        return Data(SHA256.hash(data: Data(value.utf8)))
    }
    private static func focused() -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func secure(_ element: AXUIElement) -> Bool {
        let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String
        return subrole == (kAXSecureTextFieldSubrole as String)
    }
    static func capture() throws -> TextInsertionTarget {
        guard AXIsProcessTrusted(), let element = focused(), !secure(element), let selection = range(element) else {
            throw MurmureError.message("Place the cursor in an editable, non-password text field and try dictation again. Some apps do not expose an accessible text cursor.")
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw MurmureError.message("The text field is no longer focused. Try dictation again.")
        }
        return TextInsertionTarget(element: element, pid: pid, selection: selection, fingerprint: digest(element))
    }
    func insert(_ text: String) throws -> Bool {
        guard text.utf16.count <= 16_384 else { throw MurmureError.message("This dictation is too long for automatic insertion. Copy the saved text from Murmure.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.focused(), CFEqual(element, current), !Self.secure(current),
              let range = Self.range(current), range.location == selection.location, range.length == selection.length,
              Self.digest(current) == fingerprint else {
            throw MurmureError.message("The focused field or cursor changed. Your dictation is ready to copy from Murmure.")
        }
        var writable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success, writable.boolValue {
            // One accessibility edit replaces only the captured selection.
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            guard result == .success else { throw MurmureError.message("This app refused text insertion. Your dictation is ready to copy.") }
            return true
        }
        // Unicode key events support editors without a writable SelectedText.
        // No clipboard replacement, Return key, or Send action is generated.
        guard let source = CGEventSource(stateID: .privateState) else { throw MurmureError.message("Text insertion is unavailable. Copy your dictation from Murmure.") }
        for character in text {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw MurmureError.message("Focus changed during insertion. Check the original field before copying the saved dictation.") }
            let units = Array(String(character).utf16)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { continue }
            event.flags = []
            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!) }
            event.postToPid(pid)
            event.type = .keyUp; event.postToPid(pid)
        }
        // A posted event is not proof that an editor accepted it.
        return false
    }
}
