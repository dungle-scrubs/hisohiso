import Carbon.HIToolbox
import Cocoa

// MARK: - HistoryHotkeyMonitor

/// Monitors for the history palette hotkey (Ctrl+Option+Space by default).
///
/// Uses the shared `EventTapManager` instead of creating its own CGEventTap.
/// Hotkey configuration is persisted to UserDefaults via `KeyCombo`.
final class HistoryHotkeyMonitor: @unchecked Sendable {
    private static let registrationID = "history-hotkey-monitor"

    /// Default hotkey when no saved value exists.
    static let defaultHotkey: KeyCombo = .ctrlOptionSpace

    /// Current hotkey combo.
    private(set) var currentHotkey: KeyCombo?

    /// Callback when hotkey is pressed.
    var onHotkey: (@MainActor () -> Void)?

    /// UserDefaults instance for persistence (injectable for testing).
    private let defaults: UserDefaults

    /// - Parameter defaults: UserDefaults to read/write hotkey config.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSavedHotkey()
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start monitoring for the hotkey.
    /// - Returns: true if monitoring started successfully.
    @discardableResult
    func start() -> Bool {
        guard currentHotkey != nil else {
            logDebug("No history hotkey configured, not starting monitor")
            return false
        }

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

        logInfo("HistoryHotkeyMonitor started (\(currentHotkey?.displayString ?? "none"))")
        return true
    }

    /// Stop monitoring.
    func stop() {
        EventTapManager.shared.unregister(id: Self.registrationID)
        logInfo("HistoryHotkeyMonitor stopped")
    }

    /// Update the hotkey configuration and persist it.
    /// - Parameter keyCombo: New hotkey, or `nil` to disable.
    func setHotkey(_ keyCombo: KeyCombo?) {
        stop()
        currentHotkey = keyCombo
        saveHotkey()

        if keyCombo != nil {
            start()
        }

        logInfo("History hotkey set to: \(keyCombo?.displayString ?? "disabled")")
    }

    // MARK: - Persistence

    private func loadSavedHotkey() {
        guard let data = defaults.data(for: .historyHotkey),
              let hotkey = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else {
            // No saved value — use default
            currentHotkey = Self.defaultHotkey
            return
        }
        currentHotkey = hotkey
        logInfo("Loaded saved history hotkey: \(hotkey.displayString)")
    }

    private func saveHotkey() {
        if let hotkey = currentHotkey,
           let data = try? JSONEncoder().encode(hotkey)
        {
            defaults.set(data, for: .historyHotkey)
        } else {
            defaults.remove(for: .historyHotkey)
        }
    }

    // MARK: - Event Handling

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        guard let hotkey = currentHotkey else { return false }

        let eventKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == hotkey.keyCode else { return false }

        // Compare modifiers via KeyCombo (ignoring caps lock)
        let eventCombo = KeyCombo(keyCode: eventKeyCode, flags: event.flags)
        guard eventCombo.modifiers == hotkey.modifiers else { return false }

        logDebug("History hotkey triggered")

        Task { @MainActor [weak self] in
            self?.onHotkey?()
        }

        return true
    }
}

// MARK: - Hotkey Display Helpers

extension HistoryHotkeyMonitor {
    /// Human-readable string for current hotkey.
    var displayString: String {
        currentHotkey?.displayString ?? "Disabled"
    }
}
