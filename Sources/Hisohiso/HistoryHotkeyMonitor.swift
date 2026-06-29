import Carbon.HIToolbox
import Cocoa
import os

// MARK: - HistoryHotkeyMonitor

/// Monitors for the history palette hotkey (Ctrl+Option+Space by default).
///
/// Uses the shared `EventTapManager` instead of creating its own CGEventTap.
/// Hotkey configuration is persisted to UserDefaults via `KeyCombo`.
///
/// The hotkey configuration is stored in a lock-protected field so the event tap
/// callback (which runs on an arbitrary thread) can read it safely, mirroring
/// `HotkeyManager`'s pattern.
final class HistoryHotkeyMonitor: @unchecked Sendable {
    private static let registrationID = "history-hotkey-monitor"

    /// Default hotkey when no saved value exists.
    static let defaultHotkey: KeyCombo = .ctrlOptionSpace

    /// Thread-safe copy of the hotkey for the event tap callback.
    /// The CGEventTap callback fires on an arbitrary thread and must read
    /// the hotkey synchronously to decide whether to consume the event.
    private let hotkeyLock: os.OSAllocatedUnfairLock<KeyCombo?>

    /// Current hotkey combo (nil = disabled).
    /// Reads/writes through the lock so the event tap callback stays race-free.
    var currentHotkey: KeyCombo? {
        hotkeyLock.withLock { $0 }
    }

    /// Callback when hotkey is pressed.
    var onHotkey: (@MainActor () -> Void)?

    /// UserDefaults instance for persistence (injectable for testing).
    private let defaults: UserDefaults

    /// - Parameter defaults: UserDefaults to read/write hotkey config.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkeyLock = os.OSAllocatedUnfairLock(initialState: nil)
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
            return self.handleKeyDown(event)
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
        hotkeyLock.withLock { $0 = keyCombo }
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
            hotkeyLock.withLock { $0 = Self.defaultHotkey }
            return
        }
        hotkeyLock.withLock { $0 = hotkey }
        logInfo("Loaded saved history hotkey: \(hotkey.displayString)")
    }

    private func saveHotkey() {
        let hotkey = currentHotkey
        if let hotkey,
           let data = try? JSONEncoder().encode(hotkey)
        {
            defaults.set(data, for: .historyHotkey)
        } else {
            defaults.remove(for: .historyHotkey)
        }
    }

    // MARK: - Event Handling

    /// Handle key events from the event tap callback (runs on arbitrary thread).
    /// Reads the hotkey from a lock-protected field to avoid data races.
    private nonisolated func handleKeyDown(_ event: CGEvent) -> Bool {
        // Read hotkey from thread-safe storage
        guard let hotkey = hotkeyLock.withLock({ $0 }) else { return false }

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
