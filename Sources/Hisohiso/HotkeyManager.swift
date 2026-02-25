import Carbon.HIToolbox
import Cocoa
import os

// MARK: - KeyCombo

/// Represents a keyboard shortcut combination
struct KeyCombo: Codable, Equatable, Sendable {
    /// Virtual key code (e.g., kVK_Space = 49)
    let keyCode: UInt32

    /// Modifier flags
    let modifiers: UInt32

    /// Create from raw values
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Create from CGEventFlags
    init(keyCode: UInt32, flags: CGEventFlags) {
        self.keyCode = keyCode
        modifiers = KeyCombo.carbonModifiers(from: flags)
    }

    /// Check if modifiers contain Command
    var hasCommand: Bool {
        modifiers & UInt32(cmdKey) != 0
    }

    /// Check if modifiers contain Option
    var hasOption: Bool {
        modifiers & UInt32(optionKey) != 0
    }

    /// Check if modifiers contain Control
    var hasControl: Bool {
        modifiers & UInt32(controlKey) != 0
    }

    /// Check if modifiers contain Shift
    var hasShift: Bool {
        modifiers & UInt32(shiftKey) != 0
    }

    /// Human-readable display string (e.g., "⌃⌥Space")
    var displayString: String {
        var parts: [String] = []

        if hasControl { parts.append("⌃") }
        if hasOption { parts.append("⌥") }
        if hasShift { parts.append("⇧") }
        if hasCommand { parts.append("⌘") }

        parts.append(KeyCodeUtils.keyCodeToString(UInt16(keyCode)))

        return parts.joined()
    }

    /// Convert CGEventFlags to Carbon modifiers
    private static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // MARK: - Common Presets

    static let cmdShiftSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
    static let ctrlOptionSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let ctrlShiftD = KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | shiftKey))
}

// MARK: - HotkeyManager

/// Manages the alternative dictation hotkey (in addition to Globe key).
///
/// Uses the shared `EventTapManager` instead of creating its own CGEventTap.
/// The hotkey configuration is stored in a lock-protected field so the event tap
/// callback (which runs on an arbitrary thread) can read it safely.
@MainActor
final class HotkeyManager: ObservableObject {
    /// Registration ID for EventTapManager. `nonisolated(unsafe)` allows access from `deinit`.
    private static let registrationID = "hotkey-manager"

    /// Current hotkey combo (nil = disabled). Published for UI binding.
    @Published private(set) var currentHotkey: KeyCombo?

    /// Thread-safe copy of the hotkey for the event tap callback.
    /// The CGEventTap callback fires on an arbitrary thread and must read
    /// the hotkey synchronously to decide whether to consume the event.
    private let hotkeyLock: os.OSAllocatedUnfairLock<KeyCombo?>

    /// Callback when hotkey is pressed
    var onHotkeyDown: (() -> Void)?

    /// Callback when hotkey is released
    var onHotkeyUp: (() -> Void)?

    private var isHotkeyPressed = false

    init() {
        hotkeyLock = os.OSAllocatedUnfairLock(initialState: nil)
        loadSavedHotkey()
    }

    deinit {
        EventTapManager.shared.unregister(id: Self.registrationID)
    }

    // MARK: - Public API

    /// Set or clear the alternative hotkey.
    /// - Parameter keyCombo: The key combination to use, or `nil` to disable.
    func setHotkey(_ keyCombo: KeyCombo?) {
        stop()
        currentHotkey = keyCombo
        hotkeyLock.withLock { $0 = keyCombo }
        saveHotkey()

        if keyCombo != nil {
            start()
        }

        logInfo("Alternative hotkey set to: \(keyCombo?.displayString ?? "disabled")")
    }

    /// Start monitoring for the hotkey
    @discardableResult
    func start() -> Bool {
        guard currentHotkey != nil else {
            logDebug("No hotkey configured, not starting monitor")
            return false
        }

        EventTapManager.shared.register(
            id: Self.registrationID,
            eventTypes: [.keyDown, .keyUp]
        ) { [weak self] event, type in
            guard let self else { return false }
            return handleKeyEvent(event, isDown: type == .keyDown)
        }

        EventTapManager.shared.start()

        logInfo("HotkeyManager started monitoring: \(currentHotkey?.displayString ?? "")")
        return true
    }

    /// Stop monitoring
    func stop() {
        EventTapManager.shared.unregister(id: Self.registrationID)
        isHotkeyPressed = false
        logInfo("HotkeyManager stopped")
    }

    // MARK: - Private

    /// Handle key events from the event tap callback (runs on arbitrary thread).
    /// Reads the hotkey from a lock-protected field to avoid data races.
    private nonisolated func handleKeyEvent(_ event: CGEvent, isDown: Bool) -> Bool {
        // Read hotkey from thread-safe storage (not @MainActor-isolated property)
        guard let hotkey = hotkeyLock.withLock({ $0 }) else { return false }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == hotkey.keyCode else { return false }

        // Check modifiers match exactly (ignoring caps lock)
        let currentModifiers = KeyCombo(keyCode: keyCode, flags: event.flags).modifiers
        guard currentModifiers == hotkey.modifiers else { return false }

        Task { @MainActor [weak self] in
            guard let self else { return }

            if isDown, !isHotkeyPressed {
                isHotkeyPressed = true
                logDebug("Alternative hotkey pressed: \(hotkey.displayString)")
                onHotkeyDown?()
            } else if !isDown, isHotkeyPressed {
                isHotkeyPressed = false
                logDebug("Alternative hotkey released: \(hotkey.displayString)")
                onHotkeyUp?()
            }
        }

        return true // Consume the event
    }

    private func loadSavedHotkey() {
        guard let data = UserDefaults.standard.data(for: .alternativeHotkey),
              let hotkey = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else {
            currentHotkey = nil
            return
        }
        currentHotkey = hotkey
        hotkeyLock.withLock { $0 = hotkey }
        logInfo("Loaded saved hotkey: \(hotkey.displayString)")
    }

    private func saveHotkey() {
        if let hotkey = currentHotkey,
           let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, for: .alternativeHotkey)
        } else {
            UserDefaults.standard.remove(for: .alternativeHotkey)
        }
    }
}

// MARK: - HotkeyRecorderView

/// A view that records a hotkey when clicked
final class HotkeyRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var localMonitor: Any?
    private var isRecording = false

    /// Current key combo
    var keyCombo: KeyCombo? {
        didSet { updateLabel() }
    }

    /// Callback when a new hotkey is recorded
    var onHotkeyRecorded: ((KeyCombo?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearHotkey)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),

            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateLabel()
    }

    private func updateLabel() {
        if isRecording {
            label.stringValue = "Press shortcut..."
            label.textColor = .systemBlue
            clearButton.isHidden = true
        } else if let keyCombo {
            label.stringValue = keyCombo.displayString
            label.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            label.stringValue = "Click to record"
            label.textColor = .secondaryLabelColor
            clearButton.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        updateLabel()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleRecordingEvent(event)
            return nil // Consume all events while recording
        }

        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        updateLabel()
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        guard event.type == .keyDown else { return }

        let flags = event.modifierFlags
        let hasModifier = flags.contains(.command) || flags.contains(.option) ||
            flags.contains(.control) || flags.contains(.shift)

        guard hasModifier else { return }

        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let newCombo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        stopRecording()
        keyCombo = newCombo
        onHotkeyRecorded?(newCombo)
    }

    @objc private func clearHotkey() {
        keyCombo = nil
        onHotkeyRecorded?(nil)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}
