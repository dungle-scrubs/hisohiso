import Carbon.HIToolbox
import Cocoa

// MARK: - KeyCombo

/// Represents a keyboard shortcut combination
struct KeyCombo: Codable, Equatable {
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
        self.modifiers = KeyCombo.carbonModifiers(from: flags)
    }

    /// Check if modifiers contain Command
    var hasCommand: Bool { modifiers & UInt32(cmdKey) != 0 }

    /// Check if modifiers contain Option
    var hasOption: Bool { modifiers & UInt32(optionKey) != 0 }

    /// Check if modifiers contain Control
    var hasControl: Bool { modifiers & UInt32(controlKey) != 0 }

    /// Check if modifiers contain Shift
    var hasShift: Bool { modifiers & UInt32(shiftKey) != 0 }

    /// Human-readable display string (e.g., "⌃⌥Space")
    var displayString: String {
        var parts: [String] = []

        if hasControl { parts.append("⌃") }
        if hasOption { parts.append("⌥") }
        if hasShift { parts.append("⇧") }
        if hasCommand { parts.append("⌘") }

        parts.append(keyCodeToString(keyCode))

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

    /// Convert key code to display string
    private func keyCodeToString(_ keyCode: UInt32) -> String {
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
            return characterForKeyCode(UInt16(keyCode))?.uppercased() ?? "Key\(keyCode)"
        }
    }

    /// Get character for a key code using the current keyboard layout
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

    // MARK: - Common Presets

    static let cmdShiftSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
    static let ctrlOptionSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let ctrlShiftD = KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | shiftKey))
}

// MARK: - HotkeyManager

/// Manages the alternative dictation hotkey (in addition to Globe key)
@MainActor
final class HotkeyManager: ObservableObject {
    /// Current hotkey combo (nil = disabled)
    @Published private(set) var currentHotkey: KeyCombo?

    /// Callback when hotkey is pressed
    var onHotkeyDown: (() -> Void)?

    /// Callback when hotkey is released
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyPressed = false

    private let userDefaultsKey = "alternativeHotkey"

    init() {
        loadSavedHotkey()
    }

    deinit {
        // Clean up event tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Public API

    /// Set a new hotkey
    /// - Parameter keyCombo: The key combination, or nil to disable
    func setHotkey(_ keyCombo: KeyCombo?) {
        stop()
        currentHotkey = keyCombo
        saveHotkey()

        if keyCombo != nil {
            start()
        }

        logInfo("Alternative hotkey set to: \(keyCombo?.displayString ?? "disabled")")
    }

    /// Start monitoring for the hotkey
    @discardableResult
    func start() -> Bool {
        guard let hotkey = currentHotkey else {
            logDebug("No hotkey configured, not starting monitor")
            return false
        }

        guard eventTap == nil else {
            logWarning("HotkeyManager already running")
            return true
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let consumed = manager.handleKeyEvent(event, isDown: type == .keyDown)
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logError("Failed to create event tap for HotkeyManager")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logInfo("HotkeyManager started monitoring: \(hotkey.displayString)")
        return true
    }

    /// Stop monitoring
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHotkeyPressed = false
        logInfo("HotkeyManager stopped")
    }

    // MARK: - Private

    private nonisolated func handleKeyEvent(_ event: CGEvent, isDown: Bool) -> Bool {
        guard let hotkey = MainActor.assumeIsolated({ self.currentHotkey }) else { return false }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == hotkey.keyCode else { return false }

        // Check modifiers
        let flags = event.flags
        let currentModifiers = KeyCombo(keyCode: keyCode, flags: flags).modifiers

        // Must match exactly (ignoring caps lock)
        guard currentModifiers == hotkey.modifiers else { return false }

        Task { @MainActor [weak self] in
            guard let self else { return }

            if isDown && !self.isHotkeyPressed {
                self.isHotkeyPressed = true
                logDebug("Alternative hotkey pressed: \(hotkey.displayString)")
                self.onHotkeyDown?()
            } else if !isDown && self.isHotkeyPressed {
                self.isHotkeyPressed = false
                logDebug("Alternative hotkey released: \(hotkey.displayString)")
                self.onHotkeyUp?()
            }
        }

        return true // Consume the event
    }

    private func loadSavedHotkey() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let hotkey = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else {
            currentHotkey = nil
            return
        }
        currentHotkey = hotkey
        logInfo("Loaded saved hotkey: \(hotkey.displayString)")
    }

    private func saveHotkey() {
        if let hotkey = currentHotkey,
           let data = try? JSONEncoder().encode(hotkey)
        {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
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
            clearButton.heightAnchor.constraint(equalToConstant: 16),
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

        // Also listen for escape to cancel
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
        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Only process key down with modifiers
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

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}
