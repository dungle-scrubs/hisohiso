import Cocoa
import ServiceManagement

/// Preferences window for Hisohiso settings
final class PreferencesWindow: NSWindow {
    private var modelManager: ModelManager
    private var hotkeyManager: HotkeyManager?
    private var audioFeedbackToggle: NSButton!
    private var launchAtLoginToggle: NSButton!
    private var modelPopup: NSPopUpButton!
    private var fillerWordsField: NSTextField!
    private var downloadButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var hotkeyRecorder: HotkeyRecorderView!

    init(modelManager: ModelManager, hotkeyManager: HotkeyManager? = nil) {
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        // Ensure window accepts mouse events
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = true

        title = "Hisohiso Preferences"
        isReleasedWhenClosed = false
        center()

        setupContent()
        loadSettings()
    }

    private func setupContent() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 520))
        contentView.wantsLayer = true

        var y = 470

        // MARK: - General Section
        let generalLabel = createSectionLabel("General", y: y)
        contentView.addSubview(generalLabel)
        y -= 35

        // Audio feedback toggle
        audioFeedbackToggle = NSButton(checkboxWithTitle: "Play sounds on start/stop recording", target: self, action: #selector(audioFeedbackChanged))
        audioFeedbackToggle.frame = NSRect(x: 30, y: y, width: 300, height: 20)
        contentView.addSubview(audioFeedbackToggle)
        y -= 30

        // Launch at login toggle
        launchAtLoginToggle = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginToggle.frame = NSRect(x: 30, y: y, width: 300, height: 20)
        contentView.addSubview(launchAtLoginToggle)
        y -= 50

        // MARK: - Hotkey Section
        let hotkeyLabel = createSectionLabel("Alternative Hotkey", y: y)
        contentView.addSubview(hotkeyLabel)
        y -= 35

        let hotkeyDescription = NSTextField(labelWithString: "In addition to Globe key, use this shortcut to dictate:")
        hotkeyDescription.frame = NSRect(x: 30, y: y, width: 400, height: 20)
        hotkeyDescription.font = .systemFont(ofSize: 12)
        hotkeyDescription.textColor = .secondaryLabelColor
        contentView.addSubview(hotkeyDescription)
        y -= 30

        hotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 30, y: y, width: 200, height: 28))
        hotkeyRecorder.keyCombo = hotkeyManager?.currentHotkey
        hotkeyRecorder.onHotkeyRecorded = { [weak self] keyCombo in
            self?.hotkeyManager?.setHotkey(keyCombo)
            logInfo("Alternative hotkey changed to: \(keyCombo?.displayString ?? "disabled")")
        }
        contentView.addSubview(hotkeyRecorder)
        y -= 50

        // MARK: - Transcription Section
        let transcriptionLabel = createSectionLabel("Transcription Model", y: y)
        contentView.addSubview(transcriptionLabel)
        y -= 35

        // Model selection
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.frame = NSRect(x: 30, y: y, width: 60, height: 20)
        contentView.addSubview(modelLabel)

        modelPopup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: 300, height: 25))

        // Add separator for Parakeet models
        let parakeetMenu = NSMenu()
        let parakeetHeader = NSMenuItem(title: "─── Parakeet (Best Accuracy) ───", action: nil, keyEquivalent: "")
        parakeetHeader.isEnabled = false
        parakeetMenu.addItem(parakeetHeader)

        for model in TranscriptionModel.parakeetModels {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model
            parakeetMenu.addItem(item)
        }

        // Add separator for Whisper models
        parakeetMenu.addItem(NSMenuItem.separator())
        let whisperHeader = NSMenuItem(title: "─── Whisper (Multilingual) ───", action: nil, keyEquivalent: "")
        whisperHeader.isEnabled = false
        parakeetMenu.addItem(whisperHeader)

        for model in TranscriptionModel.whisperModels {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model
            parakeetMenu.addItem(item)
        }

        modelPopup.menu = parakeetMenu
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        contentView.addSubview(modelPopup)
        y -= 35

        // Download button and progress
        downloadButton = NSButton(title: "Download Model", target: self, action: #selector(downloadModel))
        downloadButton.bezelStyle = .rounded
        downloadButton.frame = NSRect(x: 100, y: y, width: 120, height: 25)
        contentView.addSubview(downloadButton)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 230, y: y + 3, width: 170, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)
        y -= 25

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 100, y: y, width: 350, height: 20)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)
        y -= 45

        // MARK: - Formatting Section
        let formattingLabel = createSectionLabel("Text Formatting", y: y)
        contentView.addSubview(formattingLabel)
        y -= 35

        // Filler words
        let fillerLabel = NSTextField(labelWithString: "Filler words to remove (comma-separated):")
        fillerLabel.frame = NSRect(x: 30, y: y, width: 350, height: 20)
        contentView.addSubview(fillerLabel)
        y -= 55

        fillerWordsField = NSTextField(frame: NSRect(x: 30, y: y, width: 440, height: 50))
        fillerWordsField.placeholderString = "um, uh, like, you know..."
        fillerWordsField.usesSingleLineMode = false
        fillerWordsField.cell?.wraps = true
        fillerWordsField.cell?.isScrollable = false
        contentView.addSubview(fillerWordsField)
        y -= 50

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 390, y: 15, width: 80, height: 32)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        self.contentView = contentView

        // Update UI state
        updateModelUI()
    }

    private func createSectionLabel(_ text: String, y: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        return label
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        // Audio feedback (default: on)
        audioFeedbackToggle.state = defaults.object(forKey: "audioFeedbackEnabled") as? Bool ?? true ? .on : .off

        // Launch at login
        launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Model selection - find the right menu item
        selectModelInPopup(modelManager.selectedModel)

        // Filler words
        let fillerWords = defaults.stringArray(forKey: "fillerWords") ?? Array(TextFormatter.defaultFillerWords)
        fillerWordsField.stringValue = fillerWords.joined(separator: ", ")

        updateModelUI()
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
                statusLabel.stringValue = "✓ Model downloaded and ready"
                statusLabel.textColor = .systemGreen
                downloadButton.title = "Re-download"
            } else {
                statusLabel.stringValue = "Model not downloaded"
                statusLabel.textColor = .secondaryLabelColor
                downloadButton.title = "Download Model"
            }

            downloadButton.isEnabled = !modelManager.isDownloading
            progressIndicator.isHidden = !modelManager.isDownloading

            if modelManager.isDownloading {
                progressIndicator.doubleValue = modelManager.downloadProgress
            }
        }
    }

    @objc private func audioFeedbackChanged() {
        UserDefaults.standard.set(audioFeedbackToggle.state == .on, forKey: "audioFeedbackEnabled")
        logInfo("Audio feedback: \(audioFeedbackToggle.state == .on)")
    }

    @objc private func launchAtLoginChanged() {
        do {
            if launchAtLoginToggle.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logInfo("Launch at login: \(launchAtLoginToggle.state == .on)")
        } catch {
            logError("Failed to update launch at login: \(error)")
            // Revert toggle
            launchAtLoginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func modelChanged() {
        guard let model = getSelectedModel() else { return }

        UserDefaults.standard.set(model.rawValue, forKey: "selectedModel")
        modelManager.selectedModel = model
        logInfo("Model changed to: \(model.displayName)")

        updateModelUI()
    }

    @objc private func downloadModel() {
        guard let model = getSelectedModel() else { return }

        downloadButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0
        statusLabel.stringValue = "Downloading \(model.displayName)..."
        statusLabel.textColor = .secondaryLabelColor

        Task { @MainActor in
            do {
                // Monitor progress
                let progressTask = Task {
                    while modelManager.isDownloading {
                        progressIndicator.doubleValue = modelManager.downloadProgress
                        try await Task.sleep(for: .milliseconds(100))
                    }
                }

                try await modelManager.downloadModel(model)
                progressTask.cancel()

                statusLabel.stringValue = "✓ Download complete!"
                statusLabel.textColor = .systemGreen
            } catch {
                statusLabel.stringValue = "✗ Download failed: \(error.localizedDescription)"
                statusLabel.textColor = .systemRed
                logError("Download failed: \(error)")
            }

            downloadButton.isEnabled = true
            progressIndicator.isHidden = true
            updateModelUI()
        }
    }

    @objc private func saveSettings() {
        // Save filler words
        let fillerWords = fillerWordsField.stringValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(fillerWords, forKey: "fillerWords")

        // Save model selection
        modelManager.saveSelectedModel()

        logInfo("Settings saved. Filler words: \(fillerWords)")
        closeAndRestorePolicy()
    }

    override func close() {
        closeAndRestorePolicy()
    }

    private func closeAndRestorePolicy() {
        // Restore accessory policy (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        super.close()
    }
}
