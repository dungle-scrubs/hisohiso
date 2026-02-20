import Cocoa
import ServiceManagement

/// Preferences window for Hisohiso settings with tabbed interface
final class PreferencesWindow: NSWindow, NSTabViewDelegate {
    private var modelManager: ModelManager
    private var hotkeyManager: HotkeyManager?
    private var tabView: NSTabView!

    // General tab controls
    private var audioFeedbackToggle: NSButton!
    private var launchAtLoginToggle: NSButton!
    private var rustyBarToggle: NSButton!
    private let supportsLaunchAtLogin = Bundle.main.bundleURL.pathExtension == "app"
    private var floatingPillToggle: NSButton!
    private var microphonePopup: NSPopUpButton!
    private var useAudioKitToggle: NSButton!

    // Hotkey tab controls
    private var hotkeyRecorder: HotkeyRecorderView!

    // Model tab controls
    private var modelPopup: NSPopUpButton!
    private var downloadButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var fillerWordsField: NSTextField!

    // Cloud tab controls
    private var cloudFallbackToggle: NSButton!
    private var cloudProviderPopup: NSPopUpButton!
    private var openAIKeyField: NSSecureTextField!
    private var groqKeyField: NSSecureTextField!
    private var openAIStatusLabel: NSTextField!
    private var groqStatusLabel: NSTextField!

    // Voice tab controls
    private var voiceVerificationToggle: NSButton!
    private var voiceThresholdSlider: NSSlider!
    private var voiceThresholdLabel: NSTextField!
    private var voiceEnrollButton: NSButton!
    private var voiceClearButton: NSButton!
    private var voiceStatusLabel: NSTextField!
    private var enrollmentProgressLabel: NSTextField!
    private var enrollmentSamples: [[Float]] = []
    private var isRecordingEnrollment = false

    // Wake word tab controls
    private var wakeWordToggle: NSButton!
    private var wakePhraseField: NSTextField!
    private var wakeWordStatusLabel: NSTextField!

    init(modelManager: ModelManager, hotkeyManager: HotkeyManager? = nil) {
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Hisohiso Preferences"
        isReleasedWhenClosed = false
        center()

        setupTabView()
        loadSettings()
    }

    private func setupTabView() {
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        tabView.delegate = self

        // Create tabs
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = createGeneralTab()

        let hotkeyTab = NSTabViewItem(identifier: "hotkey")
        hotkeyTab.label = "Hotkey"
        hotkeyTab.view = createHotkeyTab()

        let modelTab = NSTabViewItem(identifier: "model")
        modelTab.label = "Model"
        modelTab.view = createModelTab()

        let cloudTab = NSTabViewItem(identifier: "cloud")
        cloudTab.label = "Cloud"
        cloudTab.view = createCloudTab()

        let voiceTab = NSTabViewItem(identifier: "voice")
        voiceTab.label = "Voice"
        voiceTab.view = createVoiceTab()

        let wakeWordTab = NSTabViewItem(identifier: "wakeword")
        wakeWordTab.label = "Wake Word"
        wakeWordTab.view = createWakeWordTab()

        tabView.addTabViewItem(generalTab)
        tabView.addTabViewItem(hotkeyTab)
        tabView.addTabViewItem(modelTab)
        tabView.addTabViewItem(cloudTab)
        tabView.addTabViewItem(voiceTab)
        tabView.addTabViewItem(wakeWordTab)

        contentView = tabView
    }

    // MARK: - General Tab

    private func createGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))

        var y = 280

        // Microphone selection
        let micLabel = NSTextField(labelWithString: "Microphone:")
        micLabel.frame = NSRect(x: 20, y: y, width: 100, height: 20)
        view.addSubview(micLabel)

        microphonePopup = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 300, height: 26))
        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneChanged)
        populateMicrophonePopup()
        view.addSubview(microphonePopup)
        y -= 40

        // AudioKit toggle (noise suppression)
        useAudioKitToggle = NSButton(checkboxWithTitle: "Use AudioKit (better noise handling)", target: self, action: #selector(useAudioKitChanged))
        useAudioKitToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(useAudioKitToggle)
        y -= 30

        // Audio feedback toggle
        audioFeedbackToggle = NSButton(checkboxWithTitle: "Play sounds on start/stop recording", target: self, action: #selector(audioFeedbackChanged))
        audioFeedbackToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(audioFeedbackToggle)
        y -= 30

        // Launch at login toggle
        let launchAtLoginTitle = supportsLaunchAtLogin
            ? "Launch at login"
            : "Launch at login (app bundle only)"
        launchAtLoginToggle = NSButton(checkboxWithTitle: launchAtLoginTitle, target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginToggle.isEnabled = supportsLaunchAtLogin
        launchAtLoginToggle.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(launchAtLoginToggle)
        y -= 40

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        y -= 20

        // Sinew section
        let sinewLabel = createSectionLabel("Recording Indicator", y: y)
        view.addSubview(sinewLabel)
        y -= 30

        floatingPillToggle = NSButton(checkboxWithTitle: "Show floating pill", target: self, action: #selector(floatingPillToggleChanged))
        floatingPillToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(floatingPillToggle)
        y -= 26

        rustyBarToggle = NSButton(checkboxWithTitle: "Show in Sinew", target: self, action: #selector(rustyBarToggleChanged))
        rustyBarToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(rustyBarToggle)
        y -= 22

        let sinewStatus = NSTextField(labelWithString: SinewBridge.shared.isAvailable ? "✓ Sinew detected" : "Sinew not running")
        sinewStatus.frame = NSRect(x: 40, y: y, width: 200, height: 16)
        sinewStatus.font = .systemFont(ofSize: 11)
        sinewStatus.textColor = SinewBridge.shared.isAvailable ? .systemGreen : .secondaryLabelColor
        view.addSubview(sinewStatus)
        y -= 22

        let indicatorHint = NSTextField(wrappingLabelWithString: "You can enable both to see recording status in multiple places.")
        indicatorHint.frame = NSRect(x: 40, y: y - 10, width: 380, height: 30)
        indicatorHint.font = .systemFont(ofSize: 11)
        indicatorHint.textColor = .tertiaryLabelColor
        view.addSubview(indicatorHint)

        return view
    }

    @objc private func floatingPillToggleChanged() {
        SinewBridge.shared.showFloatingPill = (floatingPillToggle.state == .on)
        logInfo("Floating pill toggled: \(floatingPillToggle.state == .on)")
    }

    @objc private func useAudioKitChanged() {
        UserDefaults.standard.set(useAudioKitToggle.state == .on, forKey: "useAudioKit")
        logInfo("AudioKit toggled: \(useAudioKitToggle.state == .on)")
    }

    private func populateMicrophonePopup() {
        microphonePopup.removeAllItems()

        let devices = AudioRecorder.availableInputDevices()
        let selectedUID = UserDefaults.standard.string(forKey: "selectedAudioDeviceUID")

        for device in devices {
            let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            item.representedObject = device
            microphonePopup.menu?.addItem(item)

            // Select current device
            if device.uid == selectedUID || (selectedUID == nil && device.uid == AudioInputDevice.systemDefault.uid) {
                microphonePopup.select(item)
            }
        }
    }

    @objc private func microphoneChanged() {
        guard let selectedItem = microphonePopup.selectedItem,
              let device = selectedItem.representedObject as? AudioInputDevice else { return }

        if device.uid == AudioInputDevice.systemDefault.uid {
            UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceUID")
        } else {
            UserDefaults.standard.set(device.uid, forKey: "selectedAudioDeviceUID")
        }

        NotificationCenter.default.post(name: .audioInputDeviceChanged, object: nil)
        logInfo("Microphone preference changed to: \(device.name)")
    }

    // MARK: - Hotkey Tab

    private func createHotkeyTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))

        var y = 260

        let description = NSTextField(wrappingLabelWithString: "The Globe key (🌐) is always active. You can also set an alternative hotkey below.")
        description.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        view.addSubview(description)
        y -= 70

        let hotkeyLabel = NSTextField(labelWithString: "Alternative Hotkey:")
        hotkeyLabel.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        view.addSubview(hotkeyLabel)

        hotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 160, y: y - 4, width: 200, height: 28))
        hotkeyRecorder.keyCombo = hotkeyManager?.currentHotkey
        hotkeyRecorder.onHotkeyRecorded = { [weak self] keyCombo in
            self?.hotkeyManager?.setHotkey(keyCombo)
            logInfo("Alternative hotkey changed to: \(keyCombo?.displayString ?? "disabled")")
        }
        view.addSubview(hotkeyRecorder)
        y -= 50

        let hint = NSTextField(wrappingLabelWithString: "Hold the hotkey to record, release to transcribe. Click the field above and press your desired key combination, or press Escape to clear.")
        hint.frame = NSRect(x: 20, y: y - 40, width: 420, height: 50)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        view.addSubview(hint)

        return view
    }

    // MARK: - Model Tab

    private func createModelTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))

        var y = 260

        // Model selection
        let modelLabel = NSTextField(labelWithString: "Transcription Model:")
        modelLabel.frame = NSRect(x: 20, y: y, width: 140, height: 20)
        view.addSubview(modelLabel)

        modelPopup = NSPopUpButton(frame: NSRect(x: 170, y: y - 2, width: 260, height: 25))
        setupModelPopup()
        view.addSubview(modelPopup)
        y -= 35

        // Download button and progress
        downloadButton = NSButton(title: "Download Model", target: self, action: #selector(downloadModel))
        downloadButton.bezelStyle = .rounded
        downloadButton.frame = NSRect(x: 170, y: y, width: 120, height: 25)
        view.addSubview(downloadButton)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 300, y: y + 3, width: 130, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isHidden = true
        view.addSubview(progressIndicator)
        y -= 25

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 170, y: y, width: 260, height: 20)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        view.addSubview(statusLabel)
        y -= 40

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        y -= 20

        // Filler words
        let fillerLabel = NSTextField(labelWithString: "Filler Words to Remove:")
        fillerLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        view.addSubview(fillerLabel)
        y -= 60

        fillerWordsField = NSTextField(frame: NSRect(x: 20, y: y, width: 420, height: 50))
        fillerWordsField.placeholderString = "um, uh, like, you know..."
        fillerWordsField.usesSingleLineMode = false
        fillerWordsField.cell?.wraps = true
        fillerWordsField.cell?.isScrollable = false
        view.addSubview(fillerWordsField)
        y -= 30

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveFillerWords))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 360, y: y, width: 80, height: 25)
        view.addSubview(saveButton)

        return view
    }

    private func setupModelPopup() {
        let menu = NSMenu()

        // Parakeet models
        let parakeetHeader = NSMenuItem(title: "── Parakeet (Best Accuracy) ──", action: nil, keyEquivalent: "")
        parakeetHeader.isEnabled = false
        menu.addItem(parakeetHeader)

        for model in TranscriptionModel.parakeetModels {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model
            menu.addItem(item)
        }

        // Whisper models
        menu.addItem(NSMenuItem.separator())
        let whisperHeader = NSMenuItem(title: "── Whisper (Multilingual) ──", action: nil, keyEquivalent: "")
        whisperHeader.isEnabled = false
        menu.addItem(whisperHeader)

        for model in TranscriptionModel.whisperModels {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model
            menu.addItem(item)
        }

        modelPopup.menu = menu
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
    }

    // MARK: - Cloud Tab

    private func createCloudTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))

        var y = 260

        let description = NSTextField(wrappingLabelWithString: "Cloud transcription is optional. Local models are always tried first. Enable fallback to use cloud when local fails.")
        description.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        view.addSubview(description)
        y -= 60

        // Cloud fallback toggle
        cloudFallbackToggle = NSButton(checkboxWithTitle: "Use cloud as fallback when local fails", target: self, action: #selector(cloudFallbackChanged))
        cloudFallbackToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(cloudFallbackToggle)
        y -= 35

        // Provider selection
        let providerLabel = NSTextField(labelWithString: "Preferred Provider:")
        providerLabel.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        view.addSubview(providerLabel)

        cloudProviderPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 150, height: 25))
        for provider in CloudProviderType.allCases {
            cloudProviderPopup.addItem(withTitle: provider.displayName)
            cloudProviderPopup.lastItem?.representedObject = provider
        }
        cloudProviderPopup.target = self
        cloudProviderPopup.action = #selector(cloudProviderChanged)
        view.addSubview(cloudProviderPopup)
        y -= 40

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        y -= 20

        // API Keys section
        let apiLabel = createSectionLabel("API Keys", y: y)
        view.addSubview(apiLabel)
        y -= 30

        // OpenAI
        let openAILabel = NSTextField(labelWithString: "OpenAI:")
        openAILabel.frame = NSRect(x: 20, y: y, width: 60, height: 20)
        view.addSubview(openAILabel)

        openAIKeyField = NSSecureTextField(frame: NSRect(x: 90, y: y - 2, width: 280, height: 22))
        openAIKeyField.placeholderString = "sk-..."
        openAIKeyField.target = self
        openAIKeyField.action = #selector(openAIKeyChanged)
        view.addSubview(openAIKeyField)

        openAIStatusLabel = NSTextField(labelWithString: "")
        openAIStatusLabel.frame = NSRect(x: 380, y: y, width: 60, height: 20)
        openAIStatusLabel.font = .systemFont(ofSize: 11)
        view.addSubview(openAIStatusLabel)
        y -= 32

        // Groq
        let groqLabel = NSTextField(labelWithString: "Groq:")
        groqLabel.frame = NSRect(x: 20, y: y, width: 60, height: 20)
        view.addSubview(groqLabel)

        groqKeyField = NSSecureTextField(frame: NSRect(x: 90, y: y - 2, width: 280, height: 22))
        groqKeyField.placeholderString = "gsk_..."
        groqKeyField.target = self
        groqKeyField.action = #selector(groqKeyChanged)
        view.addSubview(groqKeyField)

        groqStatusLabel = NSTextField(labelWithString: "")
        groqStatusLabel.frame = NSRect(x: 380, y: y, width: 60, height: 20)
        groqStatusLabel.font = .systemFont(ofSize: 11)
        view.addSubview(groqStatusLabel)

        return view
    }

    // MARK: - Voice Tab

    private func createVoiceTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))

        var y = 260

        // Enable verification toggle
        voiceVerificationToggle = NSButton(checkboxWithTitle: "Enable voice verification", target: self, action: #selector(voiceVerificationChanged))
        voiceVerificationToggle.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        view.addSubview(voiceVerificationToggle)

        let description = NSTextField(labelWithString: "Only transcribe when your voice is detected")
        description.frame = NSRect(x: 40, y: y - 18, width: 380, height: 16)
        description.font = .systemFont(ofSize: 11)
        description.textColor = .tertiaryLabelColor
        view.addSubview(description)
        y -= 45

        // Sensitivity slider
        let sensitivityLabel = NSTextField(labelWithString: "Sensitivity:")
        sensitivityLabel.frame = NSRect(x: 20, y: y, width: 80, height: 20)
        view.addSubview(sensitivityLabel)

        // Slider uses 0-100 for intuitive display, maps to 0.5-0.95 internally
        voiceThresholdSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: self, action: #selector(thresholdChanged))
        voiceThresholdSlider.frame = NSRect(x: 110, y: y, width: 200, height: 20)
        view.addSubview(voiceThresholdSlider)

        voiceThresholdLabel = NSTextField(labelWithString: "50%")
        voiceThresholdLabel.frame = NSRect(x: 320, y: y, width: 50, height: 20)
        voiceThresholdLabel.alignment = .right
        view.addSubview(voiceThresholdLabel)
        y -= 35

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        y -= 25

        // Enrollment section
        let enrollLabel = createSectionLabel("Voice Enrollment", y: y)
        view.addSubview(enrollLabel)
        y -= 25

        voiceStatusLabel = NSTextField(labelWithString: "")
        voiceStatusLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        voiceStatusLabel.font = .systemFont(ofSize: 12)
        view.addSubview(voiceStatusLabel)
        y -= 28

        voiceEnrollButton = NSButton(title: "Start Enrollment", target: self, action: #selector(startEnrollment))
        voiceEnrollButton.bezelStyle = .rounded
        voiceEnrollButton.frame = NSRect(x: 20, y: y, width: 130, height: 25)
        view.addSubview(voiceEnrollButton)

        voiceClearButton = NSButton(title: "Clear", target: self, action: #selector(clearEnrollment))
        voiceClearButton.bezelStyle = .rounded
        voiceClearButton.frame = NSRect(x: 160, y: y, width: 80, height: 25)
        view.addSubview(voiceClearButton)
        y -= 28

        enrollmentProgressLabel = NSTextField(labelWithString: "Speak naturally for 5-10 seconds to enroll your voice")
        enrollmentProgressLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        enrollmentProgressLabel.font = .systemFont(ofSize: 11)
        enrollmentProgressLabel.textColor = .secondaryLabelColor
        view.addSubview(enrollmentProgressLabel)

        return view
    }

    // MARK: - Wake Word Tab

    private func createWakeWordTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 340))
        var y = 290

        // Section: Wake Word Detection
        view.addSubview(createSectionLabel("Wake Word Detection", y: y))
        y -= 30

        // Enable toggle
        wakeWordToggle = NSButton(checkboxWithTitle: "Enable wake word detection", target: self, action: #selector(wakeWordToggleChanged))
        wakeWordToggle.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        view.addSubview(wakeWordToggle)
        y -= 25

        let descLabel = NSTextField(wrappingLabelWithString: "Say your wake phrase to start recording without pressing any keys. Uses Whisper tiny for continuous listening.")
        descLabel.frame = NSRect(x: 40, y: y - 20, width: 380, height: 40)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        view.addSubview(descLabel)
        y -= 60

        // Wake phrase
        let phraseLabel = NSTextField(labelWithString: "Wake Phrase:")
        phraseLabel.frame = NSRect(x: 20, y: y, width: 100, height: 20)
        view.addSubview(phraseLabel)

        wakePhraseField = NSTextField(frame: NSRect(x: 130, y: y, width: 200, height: 22))
        wakePhraseField.placeholderString = "hey hisohiso"
        wakePhraseField.target = self
        wakePhraseField.action = #selector(wakePhraseChanged)
        view.addSubview(wakePhraseField)
        y -= 30

        let examplesLabel = NSTextField(wrappingLabelWithString: "Examples: \"hey computer\", \"hey kevin\", \"dictate\"")
        examplesLabel.frame = NSRect(x: 130, y: y, width: 300, height: 20)
        examplesLabel.font = .systemFont(ofSize: 11)
        examplesLabel.textColor = .tertiaryLabelColor
        view.addSubview(examplesLabel)
        y -= 40

        // Status
        wakeWordStatusLabel = NSTextField(labelWithString: "")
        wakeWordStatusLabel.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        wakeWordStatusLabel.font = .systemFont(ofSize: 11)
        wakeWordStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(wakeWordStatusLabel)
        y -= 40

        // Warning about battery
        let warningLabel = NSTextField(wrappingLabelWithString: "⚠️ Wake word detection keeps the microphone active and uses some CPU. This may impact battery life on laptops.")
        warningLabel.frame = NSRect(x: 20, y: y - 20, width: 400, height: 40)
        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        view.addSubview(warningLabel)

        // Load current settings
        let enabled = UserDefaults.standard.bool(forKey: "wakeWordEnabled")
        wakeWordToggle.state = enabled ? .on : .off
        wakePhraseField.stringValue = UserDefaults.standard.string(forKey: "wakePhrase") ?? "hey hisohiso"
        updateWakeWordStatus()

        return view
    }

    private func updateWakeWordStatus() {
        let enabled = wakeWordToggle.state == .on
        if enabled {
            wakeWordStatusLabel.stringValue = "Wake word detection is active. Say \"\(wakePhraseField.stringValue)\" to start recording."
            wakeWordStatusLabel.textColor = .systemGreen
        } else {
            wakeWordStatusLabel.stringValue = "Wake word detection is disabled."
            wakeWordStatusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func wakeWordToggleChanged() {
        UserDefaults.standard.set(wakeWordToggle.state == .on, forKey: "wakeWordEnabled")
        updateWakeWordStatus()
        NotificationCenter.default.post(name: .wakeWordSettingsChanged, object: nil)
    }

    @objc private func wakePhraseChanged() {
        let phrase = wakePhraseField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(phrase, forKey: "wakePhrase")
        updateWakeWordStatus()
        NotificationCenter.default.post(name: .wakeWordSettingsChanged, object: nil)
    }

    // MARK: - Helpers

    private func createSectionLabel(_ text: String, y: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        return label
    }

    // MARK: - Load Settings

    private func loadSettings() {
        let defaults = UserDefaults.standard

        // General
        audioFeedbackToggle.state = defaults.object(forKey: "audioFeedbackEnabled") as? Bool ?? true ? .on : .off
        launchAtLoginToggle.state = supportsLaunchAtLogin && SMAppService.mainApp.status == .enabled ? .on : .off
        floatingPillToggle.state = SinewBridge.shared.showFloatingPill ? .on : .off
        rustyBarToggle.state = SinewBridge.shared.useSinewVisualization ? .on : .off
        rustyBarToggle.isEnabled = SinewBridge.shared.isAvailable
        useAudioKitToggle.state = defaults.bool(forKey: "useAudioKit") ? .on : .off

        // Model
        selectModelInPopup(modelManager.selectedModel)
        let fillerWords = defaults.stringArray(forKey: "fillerWords") ?? Array(TextFormatter.defaultFillerWords)
        fillerWordsField.stringValue = fillerWords.joined(separator: ", ")
        updateModelUI()

        // Cloud
        let cloudSettings = CloudFallbackSettings.load()
        cloudFallbackToggle.state = cloudSettings.enabled ? .on : .off
        for (index, item) in cloudProviderPopup.itemArray.enumerated() {
            if let provider = item.representedObject as? CloudProviderType, provider == cloudSettings.preferredProvider {
                cloudProviderPopup.selectItem(at: index)
                break
            }
        }
        updateCloudKeyStatus()

        // Voice
        voiceVerificationToggle.state = VoiceVerifier.shared.isEnabled ? .on : .off
        // Map internal 0.5-0.95 to display 0-100
        let displayValue = (VoiceVerifier.shared.threshold - 0.5) / 0.45 * 100
        voiceThresholdSlider.floatValue = displayValue
        updateThresholdLabel()
        updateVoiceStatus()
    }

    private func updateThresholdLabel() {
        let percentage = Int(voiceThresholdSlider.floatValue)
        voiceThresholdLabel.stringValue = "\(percentage)%"
    }

    private func updateVoiceStatus() {
        if VoiceVerifier.shared.isEnrolled {
            voiceStatusLabel.stringValue = "✓ Voice enrolled"
            voiceStatusLabel.textColor = .systemGreen
            voiceEnrollButton.title = "Re-enroll"
            voiceClearButton.isEnabled = true
        } else {
            voiceStatusLabel.stringValue = "No voice enrolled"
            voiceStatusLabel.textColor = .secondaryLabelColor
            voiceEnrollButton.title = "Start Enrollment"
            voiceClearButton.isEnabled = false
        }
    }

    private func selectModelInPopup(_ model: TranscriptionModel) {
        guard let menu = modelPopup.menu else { return }
        for (index, item) in menu.items.enumerated() {
            if let itemModel = item.representedObject as? TranscriptionModel, itemModel == model {
                modelPopup.selectItem(at: index)
                return
            }
        }
    }

    private func getSelectedModel() -> TranscriptionModel? {
        guard let selectedItem = modelPopup.selectedItem,
              let model = selectedItem.representedObject as? TranscriptionModel else {
            return nil
        }
        return model
    }

    private func updateModelUI() {
        guard let model = getSelectedModel() else { return }

        Task { @MainActor in
            let isDownloaded = await modelManager.isModelDownloaded(model)

            if isDownloaded {
                statusLabel.stringValue = "✓ Downloaded and ready"
                statusLabel.textColor = .systemGreen
                downloadButton.title = "Re-download"
            } else {
                statusLabel.stringValue = "Not downloaded"
                statusLabel.textColor = .secondaryLabelColor
                downloadButton.title = "Download"
            }

            downloadButton.isEnabled = !modelManager.isDownloading
            progressIndicator.isHidden = !modelManager.isDownloading
        }
    }

    private func updateCloudKeyStatus() {
        if KeychainManager.shared.hasAPIKey(.openAI) {
            openAIStatusLabel.stringValue = "✓ Set"
            openAIStatusLabel.textColor = .systemGreen
            openAIKeyField.placeholderString = "••••••••"
        } else {
            openAIStatusLabel.stringValue = "Not set"
            openAIStatusLabel.textColor = .secondaryLabelColor
            openAIKeyField.placeholderString = "sk-..."
        }

        if KeychainManager.shared.hasAPIKey(.groq) {
            groqStatusLabel.stringValue = "✓ Set"
            groqStatusLabel.textColor = .systemGreen
            groqKeyField.placeholderString = "••••••••"
        } else {
            groqStatusLabel.stringValue = "Not set"
            groqStatusLabel.textColor = .secondaryLabelColor
            groqKeyField.placeholderString = "gsk_..."
        }
    }

    // MARK: - Actions

    @objc private func audioFeedbackChanged() {
        UserDefaults.standard.set(audioFeedbackToggle.state == .on, forKey: "audioFeedbackEnabled")
        logInfo("Audio feedback: \(audioFeedbackToggle.state == .on)")
    }

    @objc private func launchAtLoginChanged() {
        guard supportsLaunchAtLogin else {
            launchAtLoginToggle.state = .off
            logWarning("Launch at login unavailable outside app bundle builds")
            return
        }

        do {
            if launchAtLoginToggle.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logInfo("Launch at login: \(launchAtLoginToggle.state == .on)")
        } catch {
            logError("Failed to update launch at login: \(error)")
            launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func rustyBarToggleChanged() {
        SinewBridge.shared.useSinewVisualization = rustyBarToggle.state == .on
        logInfo("Sinew visualization: \(rustyBarToggle.state == .on)")
    }

    @objc private func modelChanged() {
        guard let model = getSelectedModel() else { return }

        modelManager.selectedModel = model
        modelManager.saveSelectedModel()
        NotificationCenter.default.post(name: .modelSelectionChanged, object: nil)

        logInfo("Model changed to: \(model.displayName)")
        updateModelUI()
    }

    @objc private func downloadModel() {
        guard let model = getSelectedModel() else { return }

        downloadButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0
        statusLabel.stringValue = "Downloading..."
        statusLabel.textColor = .secondaryLabelColor

        Task { @MainActor in
            let progressTask = Task {
                while !Task.isCancelled {
                    progressIndicator.doubleValue = modelManager.downloadProgress
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { progressTask.cancel() }

            do {
                try await modelManager.downloadModel(model)
                statusLabel.stringValue = "✓ Download complete!"
                statusLabel.textColor = .systemGreen
            } catch {
                statusLabel.stringValue = "✗ Failed: \(error.localizedDescription)"
                statusLabel.textColor = .systemRed
                logError("Download failed: \(error)")
            }

            downloadButton.isEnabled = true
            progressIndicator.isHidden = true
            updateModelUI()
        }
    }

    @objc private func saveFillerWords() {
        let fillerWords = fillerWordsField.stringValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(fillerWords, forKey: "fillerWords")
        logInfo("Filler words saved: \(fillerWords)")
    }

    @objc private func cloudFallbackChanged() {
        var settings = CloudFallbackSettings.load()
        settings.enabled = cloudFallbackToggle.state == .on
        settings.save()
        logInfo("Cloud fallback: \(settings.enabled)")
    }

    @objc private func cloudProviderChanged() {
        guard let selectedItem = cloudProviderPopup.selectedItem,
              let provider = selectedItem.representedObject as? CloudProviderType else {
            return
        }
        var settings = CloudFallbackSettings.load()
        settings.preferredProvider = provider
        settings.save()
        logInfo("Cloud provider: \(provider.displayName)")
    }

    @objc private func openAIKeyChanged() {
        let key = openAIKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            _ = KeychainManager.shared.deleteAPIKey(.openAI)
        } else {
            _ = KeychainManager.shared.setAPIKey(key, type: .openAI)
        }
        openAIKeyField.stringValue = ""
        updateCloudKeyStatus()
    }

    @objc private func groqKeyChanged() {
        let key = groqKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            _ = KeychainManager.shared.deleteAPIKey(.groq)
        } else {
            _ = KeychainManager.shared.setAPIKey(key, type: .groq)
        }
        groqKeyField.stringValue = ""
        updateCloudKeyStatus()
    }

    // MARK: - Voice Actions

    @objc private func voiceVerificationChanged() {
        VoiceVerifier.shared.isEnabled = voiceVerificationToggle.state == .on
        logInfo("Voice verification: \(VoiceVerifier.shared.isEnabled)")
    }

    @objc private func thresholdChanged() {
        // Map display 0-100 to internal 0.5-0.95
        let internalValue = 0.5 + (voiceThresholdSlider.floatValue / 100) * 0.45
        VoiceVerifier.shared.threshold = internalValue
        updateThresholdLabel()
        logInfo("Voice threshold: \(internalValue) (display: \(Int(voiceThresholdSlider.floatValue))%)")
    }

    @objc private func startEnrollment() {
        if isRecordingEnrollment {
            // Stop recording and process
            stopEnrollmentRecording()
        } else {
            // Start enrollment process
            beginEnrollment()
        }
    }

    private func beginEnrollment() {
        enrollmentSamples = []
        isRecordingEnrollment = true
        voiceEnrollButton.title = "Stop Recording"
        voiceClearButton.isEnabled = false
        enrollmentProgressLabel.stringValue = "🎤 Speak naturally for 5-10 seconds... (0 samples)"
        enrollmentProgressLabel.textColor = .systemRed

        // Start recording using AudioRecorder
        // We'll collect samples and then enroll
        collectEnrollmentSample()
    }

    private func collectEnrollmentSample() {
        guard isRecordingEnrollment else { return }

        // Use a temporary audio recorder for enrollment
        let recorder = AudioRecorder()
        do {
            try recorder.startRecording()

            // Record for 2.5 seconds per sample
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.isRecordingEnrollment else { return }

                let samples = recorder.stopRecording()
                if samples.count >= VoiceVerifier.minSamplesForVerification {
                    self.enrollmentSamples.append(samples)
                    self.enrollmentProgressLabel.stringValue = "🎤 Keep speaking... (\(self.enrollmentSamples.count) samples)"
                }

                // Collect more samples if under target
                if self.enrollmentSamples.count < 3 {
                    self.collectEnrollmentSample()
                } else {
                    // Auto-stop after 3 good samples
                    self.stopEnrollmentRecording()
                }
            }
        } catch {
            logError("Failed to start enrollment recording: \(error)")
            enrollmentProgressLabel.stringValue = "✗ Failed to access microphone"
            enrollmentProgressLabel.textColor = .systemRed
            isRecordingEnrollment = false
            voiceEnrollButton.title = "Start Enrollment"
        }
    }

    private func stopEnrollmentRecording() {
        isRecordingEnrollment = false
        voiceEnrollButton.title = "Processing..."
        voiceEnrollButton.isEnabled = false

        guard !enrollmentSamples.isEmpty else {
            enrollmentProgressLabel.stringValue = "✗ No audio captured"
            enrollmentProgressLabel.textColor = .systemRed
            voiceEnrollButton.title = "Start Enrollment"
            voiceEnrollButton.isEnabled = true
            return
        }

        // Enroll with collected samples
        Task { @MainActor in
            do {
                try VoiceVerifier.shared.enroll(with: enrollmentSamples)
                enrollmentProgressLabel.stringValue = "✓ Enrollment complete!"
                enrollmentProgressLabel.textColor = .systemGreen
                updateVoiceStatus()
            } catch {
                enrollmentProgressLabel.stringValue = "✗ \(error.localizedDescription)"
                enrollmentProgressLabel.textColor = .systemRed
                logError("Enrollment failed: \(error)")
            }

            voiceEnrollButton.isEnabled = true
            updateVoiceStatus()
        }
    }

    @objc private func clearEnrollment() {
        VoiceVerifier.shared.clearEnrollment()
        enrollmentProgressLabel.stringValue = ""
        updateVoiceStatus()
        logInfo("Voice enrollment cleared")
    }

    // MARK: - Window Lifecycle

    override func close() {
        // Stop any ongoing enrollment
        isRecordingEnrollment = false

        NSApp.setActivationPolicy(.accessory)
        super.close()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let wakeWordSettingsChanged = Notification.Name("wakeWordSettingsChanged")
    static let modelSelectionChanged = Notification.Name("modelSelectionChanged")
    static let audioInputDeviceChanged = Notification.Name("audioInputDeviceChanged")
}
