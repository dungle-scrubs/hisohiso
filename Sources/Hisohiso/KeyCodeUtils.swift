import Carbon.HIToolbox
import Foundation

/// Shared utilities for converting key codes to display strings.
///
/// Extracted from `HotkeyManager` and `HistoryHotkeyMonitor` to eliminate
/// duplicated `keyCodeToString` / `characterForKeyCode` implementations.
enum KeyCodeUtils {
    /// Convert a virtual key code to a human-readable string.
    /// - Parameter keyCode: The virtual key code (e.g., `kVK_Space`).
    /// - Returns: A display string (e.g., "Space", "⌘", "A").
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↵"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_Escape: "⎋"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_Home: "↖"
        case kVK_End: "↘"
        case kVK_PageUp: "⇞"
        case kVK_PageDown: "⇟"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default:
            characterForKeyCode(keyCode)?.uppercased() ?? "Key\(keyCode)"
        }
    }

    /// Get the character for a key code using the current keyboard layout.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The character string, or nil if not mappable.
    static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let result = data.withUnsafeBytes { ptr -> OSStatus in
            guard let layoutPtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecParam
            }
            return UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
