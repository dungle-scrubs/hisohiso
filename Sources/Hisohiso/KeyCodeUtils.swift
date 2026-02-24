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
        case kVK_Space: return "Space"
        case kVK_Return: return "↵"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return characterForKeyCode(keyCode)?.uppercased() ?? "Key\(keyCode)"
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
