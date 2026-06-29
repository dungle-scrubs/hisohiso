import Cocoa
import ServiceManagement

/// General preferences tab: microphone, audio feedback, launch at login, recording indicators.
final class GeneralPreferencesTab: NSView {
    private var audioFeedbackToggle: NSButton!
    private var launchAtLoginToggle: NSButton!
    private var floatingPillToggle: NSButton!
    private var microphonePopup: NSPopUpButton!
    private var useAudioKitToggle: NSButton!
    private var pauseMediaToggle: NSButton!
    private let supportsLaunchAtLogin = Bundle.main.bundleURL.pathExtension == "app"
    private let preferences = AppPreferences.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        var y = 280

        let micLabel = NSTextField(labelWithString: "Microphone:")
        micLabel.frame = NSRect(x: 20, y: y, width: 100, height: 20)
        addSubview(micLabel)

        microphonePopup = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 300, height: 26))
        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneChanged)
        populateMicrophonePopup()
        addSubview(microphonePopup)
        y -= 40

        useAudioKitToggle = NSButton(
            checkboxWithTitle: "Use AudioKit (better noise handling)",
            target: self,
            action: #selector(useAudioKitChanged)
        )
        useAudioKitToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        addSubview(useAudioKitToggle)
        y -= 30

        audioFeedbackToggle = NSButton(
            checkboxWithTitle: "Play sounds on start/stop recording",
            target: self,
            action: #selector(audioFeedbackChanged)
        )
        audioFeedbackToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        addSubview(audioFeedbackToggle)
        y -= 30

        pauseMediaToggle = NSButton(
            checkboxWithTitle: "Pause media while recording (Music, Spotify, browsers)",
            target: self,
            action: #selector(pauseMediaChanged)
        )
        pauseMediaToggle.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        addSubview(pauseMediaToggle)
        y -= 30

        let launchTitle = supportsLaunchAtLogin ? "Launch at login" : "Launch at login (app bundle only)"
        launchAtLoginToggle = NSButton(
            checkboxWithTitle: launchTitle,
            target: self,
            action: #selector(launchAtLoginChanged)
        )
        launchAtLoginToggle.isEnabled = supportsLaunchAtLogin
        launchAtLoginToggle.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        addSubview(launchAtLoginToggle)
        y -= 40

        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        addSubview(separator)
        y -= 20

        let sectionLabel = NSTextField(labelWithString: "Recording Indicator")
        sectionLabel.font = .boldSystemFont(ofSize: 12)
        sectionLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        addSubview(sectionLabel)
        y -= 30

        floatingPillToggle = NSButton(
            checkboxWithTitle: "Show floating pill",
            target: self,
            action: #selector(floatingPillToggleChanged)
        )
        floatingPillToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        addSubview(floatingPillToggle)
    }

    /// Load current settings into controls.
    func loadSettings() {
        audioFeedbackToggle
            .state = (
                preferences.audioFeedbackEnabled
            ) ?
            .on : .off
        launchAtLoginToggle.state = supportsLaunchAtLogin && SMAppService.mainApp.status == .enabled ? .on : .off
        floatingPillToggle.state = preferences.showFloatingPill ? .on : .off
        useAudioKitToggle.state = preferences.useAudioKit ? .on : .off
        pauseMediaToggle.state = preferences.pauseMediaDuringRecording ? .on : .off
    }

    // MARK: - Actions

    private func populateMicrophonePopup() {
        microphonePopup.removeAllItems()
        let devices = AudioRecorder.availableInputDevices()
        let selectedUID = preferences.selectedAudioDeviceUID
        for device in devices {
            let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            item.representedObject = device
            microphonePopup.menu?.addItem(item)
            if device.uid == selectedUID || (selectedUID == nil && device.uid == AudioInputDevice.systemDefault.uid) {
                microphonePopup.select(item)
            }
        }
    }

    @objc private func microphoneChanged() {
        guard let selectedItem = microphonePopup.selectedItem,
              let device = selectedItem.representedObject as? AudioInputDevice else { return }
        preferences.selectAudioDevice(device)
        logInfo("Microphone preference changed to: \(device.name)")
    }

    @objc private func useAudioKitChanged() {
        preferences.useAudioKit = useAudioKitToggle.state == .on
    }

    @objc private func audioFeedbackChanged() {
        preferences.audioFeedbackEnabled = audioFeedbackToggle.state == .on
    }

    @objc private func pauseMediaChanged() {
        preferences.pauseMediaDuringRecording = pauseMediaToggle.state == .on
    }

    @objc private func launchAtLoginChanged() {
        guard supportsLaunchAtLogin else { launchAtLoginToggle.state = .off; return }
        do {
            if launchAtLoginToggle.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            logError("Failed to update launch at login: \(error)")
            launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func floatingPillToggleChanged() {
        preferences.showFloatingPill = (floatingPillToggle.state == .on)
    }
}
