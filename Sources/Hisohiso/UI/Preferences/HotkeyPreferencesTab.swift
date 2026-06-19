import Cocoa

/// Hotkey preferences tab: alternative hotkey and history palette hotkey configuration.
final class HotkeyPreferencesTab: NSView {
    private var dictationRecorder: HotkeyRecorderView!
    private var historyRecorder: HotkeyRecorderView!
    private weak var hotkeyManager: HotkeyManager?
    private weak var historyHotkeyMonitor: HistoryHotkeyMonitor?

    /// - Parameters:
    ///   - hotkeyManager: Manager to configure when dictation hotkey changes.
    ///   - historyHotkeyMonitor: Monitor to configure when history hotkey changes.
    init(hotkeyManager: HotkeyManager?, historyHotkeyMonitor: HistoryHotkeyMonitor?) {
        self.hotkeyManager = hotkeyManager
        self.historyHotkeyMonitor = historyHotkeyMonitor
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 340))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        var y = 260

        // Description
        let description =
            NSTextField(
                wrappingLabelWithString: "The Globe key (🌐) is always active. You can also set an alternative hotkey below."
            )
        description.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        addSubview(description)
        y -= 70

        // MARK: Dictation Hotkey

        let dictationLabel = NSTextField(labelWithString: "Alternative Hotkey:")
        dictationLabel.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        addSubview(dictationLabel)

        dictationRecorder = HotkeyRecorderView(frame: NSRect(x: 160, y: y - 4, width: 200, height: 28))
        dictationRecorder.keyCombo = hotkeyManager?.currentHotkey
        dictationRecorder.onHotkeyRecorded = { [weak self] keyCombo in
            self?.hotkeyManager?.setHotkey(keyCombo)
            logInfo("Alternative hotkey changed to: \(keyCombo?.displayString ?? "disabled")")
        }
        addSubview(dictationRecorder)
        y -= 40

        let dictationHint =
            NSTextField(
                wrappingLabelWithString: "Hold the hotkey to record, release to transcribe. Click the field above and press your desired key combination, or press Escape to clear."
            )
        dictationHint.frame = NSRect(x: 20, y: y - 40, width: 420, height: 50)
        dictationHint.font = .systemFont(ofSize: 11)
        dictationHint.textColor = .tertiaryLabelColor
        addSubview(dictationHint)
        y -= 70

        // Divider
        let divider = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        divider.boxType = .separator
        addSubview(divider)
        y -= 30

        // MARK: History Palette Hotkey

        let historyLabel = NSTextField(labelWithString: "History Palette:")
        historyLabel.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        addSubview(historyLabel)

        historyRecorder = HotkeyRecorderView(frame: NSRect(x: 160, y: y - 4, width: 200, height: 28))
        historyRecorder.keyCombo = historyHotkeyMonitor?.currentHotkey
        historyRecorder.onHotkeyRecorded = { [weak self] keyCombo in
            self?.historyHotkeyMonitor?.setHotkey(keyCombo)
            logInfo("History hotkey changed to: \(keyCombo?.displayString ?? "disabled")")
        }
        addSubview(historyRecorder)
        y -= 40

        let historyHint =
            NSTextField(
                wrappingLabelWithString: "Opens a Spotlight-style search for your recent transcriptions. Press the hotkey to toggle."
            )
        historyHint.frame = NSRect(x: 20, y: y - 20, width: 420, height: 34)
        historyHint.font = .systemFont(ofSize: 11)
        historyHint.textColor = .tertiaryLabelColor
        addSubview(historyHint)
    }
}
