import Carbon.HIToolbox
import Cocoa

// MARK: - HistoryHotkeyMonitor

/// Monitors for the history palette hotkey (Ctrl+Option+Space by default)
final class HistoryHotkeyMonitor {
    /// Callback when hotkey is pressed
    var onHotkey: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Current hotkey configuration
    private(set) var keyCode: UInt16 = UInt16(kVK_Space)
    private(set) var modifiers: CGEventFlags = [.maskControl, .maskAlternate]

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start monitoring for the hotkey
    /// - Returns: true if monitoring started successfully
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            logWarning("HistoryHotkeyMonitor already running")
            return true
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }

                let monitor = Unmanaged<HistoryHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                if monitor.handleKeyDown(event) {
                    // Consume the event
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            logError("Failed to create event tap for history hotkey")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)

        logInfo("HistoryHotkeyMonitor started (Ctrl+Option+Space)")
        return true
    }

    /// Stop monitoring
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil

        logInfo("HistoryHotkeyMonitor stopped")
    }

    /// Update the hotkey configuration
    /// - Parameters:
    ///   - keyCode: The key code (e.g., kVK_Space)
    ///   - modifiers: The modifier flags (e.g., [.maskControl, .maskAlternate])
    func setHotkey(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        logInfo("History hotkey updated: keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")
    }

    // MARK: - Private

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = event.flags

        // Check if key code matches
        guard eventKeyCode == keyCode else { return false }

        // Check if required modifiers are pressed
        // We want exactly these modifiers (with some tolerance for caps lock, etc.)
        let relevantModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        let pressedRelevant = eventModifiers.intersection(relevantModifiers)
        let requiredRelevant = modifiers.intersection(relevantModifiers)

        guard pressedRelevant == requiredRelevant else { return false }

        logDebug("History hotkey triggered")

        // Dispatch to main thread
        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?()
        }

        return true
    }
}

// MARK: - Hotkey Display Helpers

extension HistoryHotkeyMonitor {
    /// Human-readable string for current hotkey
    var displayString: String {
        var parts: [String] = []

        if modifiers.contains(.maskControl) {
            parts.append("⌃")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("⌥")
        }
        if modifiers.contains(.maskShift) {
            parts.append("⇧")
        }
        if modifiers.contains(.maskCommand) {
            parts.append("⌘")
        }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↵"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        default:
            // Try to get character from key code
            if let char = characterForKeyCode(keyCode) {
                return char.uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    private func characterForKeyCode(_ keyCode: UInt16) -> String? {
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
