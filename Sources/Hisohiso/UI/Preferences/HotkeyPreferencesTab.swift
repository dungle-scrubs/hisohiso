import Cocoa

/// Hotkey preferences tab: alternative hotkey configuration.
final class HotkeyPreferencesTab: NSView {
    private var hotkeyRecorder: HotkeyRecorderView!
    private weak var hotkeyManager: HotkeyManager?

    /// - Parameter hotkeyManager: Manager to configure when hotkey changes.
    init(hotkeyManager: HotkeyManager?) {
        self.hotkeyManager = hotkeyManager
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 340))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        var y = 260

        let description = NSTextField(wrappingLabelWithString: "The Globe key (🌐) is always active. You can also set an alternative hotkey below.")
        description.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        addSubview(description)
        y -= 70

        let label = NSTextField(labelWithString: "Alternative Hotkey:")
        label.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        addSubview(label)

        hotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 160, y: y - 4, width: 200, height: 28))
        hotkeyRecorder.keyCombo = hotkeyManager?.currentHotkey
        hotkeyRecorder.onHotkeyRecorded = { [weak self] keyCombo in
            self?.hotkeyManager?.setHotkey(keyCombo)
            logInfo("Alternative hotkey changed to: \(keyCombo?.displayString ?? "disabled")")
        }
        addSubview(hotkeyRecorder)
        y -= 50

        let hint = NSTextField(wrappingLabelWithString: "Hold the hotkey to record, release to transcribe. Click the field above and press your desired key combination, or press Escape to clear.")
        hint.frame = NSRect(x: 20, y: y - 40, width: 420, height: 50)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        addSubview(hint)
    }
}
