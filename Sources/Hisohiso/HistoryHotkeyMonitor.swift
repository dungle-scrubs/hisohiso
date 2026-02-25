import Carbon.HIToolbox
import Cocoa

// MARK: - HistoryHotkeyMonitor

/// Monitors for the history palette hotkey (Ctrl+Option+Space by default).
///
/// Uses the shared `EventTapManager` instead of creating its own CGEventTap.
final class HistoryHotkeyMonitor {
    private static let registrationID = "history-hotkey-monitor"

    /// Callback when hotkey is pressed
    var onHotkey: (() -> Void)?

    /// Current hotkey configuration
    private(set) var keyCode: UInt16 = .init(kVK_Space)
    private(set) var modifiers: CGEventFlags = [.maskControl, .maskAlternate]

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start monitoring for the hotkey
    /// - Returns: true if monitoring started successfully
    @discardableResult
    func start() -> Bool {
        EventTapManager.shared.register(
            id: Self.registrationID,
            eventTypes: [.keyDown]
        ) { [weak self] event, _ in
            guard let self else { return false }
            return handleKeyDown(event)
        }

        guard EventTapManager.shared.start() else {
            logError("Failed to start event tap for history hotkey")
            return false
        }

        logInfo("HistoryHotkeyMonitor started (\(displayString))")
        return true
    }

    /// Stop monitoring
    func stop() {
        EventTapManager.shared.unregister(id: Self.registrationID)
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
        guard eventKeyCode == keyCode else { return false }

        // Check if required modifiers are pressed exactly (with tolerance for caps lock)
        let relevantModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        let pressedRelevant = event.flags.intersection(relevantModifiers)
        let requiredRelevant = modifiers.intersection(relevantModifiers)
        guard pressedRelevant == requiredRelevant else { return false }

        logDebug("History hotkey triggered")

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

        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }

        parts.append(KeyCodeUtils.keyCodeToString(keyCode))

        return parts.joined()
    }
}
