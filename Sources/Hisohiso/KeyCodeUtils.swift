import Carbon.HIToolbox
import Foundation

/// Shared utilities for converting key codes to display strings.
///
/// Extracted from `HotkeyManager` and `HistoryHotkeyMonitor` to eliminate
/// duplicated `keyCodeToString` / `characterForKeyCode` implementations.
enum KeyCodeUtils {
    /// Display names for keys that have no printable character or whose
    /// character is replaced by a conventional symbol.
    private static let fixedNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↵",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Convert a virtual key code to a human-readable string.
    /// - Parameter keyCode: The virtual key code (e.g., `kVK_Space`).
    /// - Returns: A display string (e.g., "Space", "⌘", "A").
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        if let name = fixedNames[Int(keyCode)] {
            return name
        }
        return characterForKeyCode(keyCode)?.uppercased() ?? "Key\(keyCode)"
    }

    /// Virtual key codes for F1 through F20.
    ///
    /// These produce no character, so they are safe to bind without a modifier.
    static let functionKeyCodes: Set<UInt16> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map { UInt16($0) }.reduce(into: []) { $0.insert($1) }

    /// Whether a virtual key code is one of F1 through F20.
    /// - Parameter keyCode: The virtual key code.
    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(keyCode)
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
