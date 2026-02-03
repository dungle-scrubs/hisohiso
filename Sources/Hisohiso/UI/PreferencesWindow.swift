import Cocoa
import ServiceManagement

/// Preferences window for Hisohiso settings
final class PreferencesWindow: NSWindow {
    private var modelManager: ModelManager
    private var audioFeedbackToggle: NSButton!
    private var launchAtLoginToggle: NSButton!
    private var modelPopup: NSPopUpButton!
    private var fillerWordsField: NSTextField!
    
    init(modelManager: ModelManager) {
        self.modelManager = modelManager
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        title = "Hisohiso Preferences"
        isReleasedWhenClosed = false
        center()
        
        setupContent()
        loadSettings()
    }
    
    private func setupContent() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 320))
        
        var y = 270
        
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
        y -= 45
        
        // MARK: - Transcription Section
        let transcriptionLabel = createSectionLabel("Transcription", y: y)
        contentView.addSubview(transcriptionLabel)
        y -= 35
        
        // Model selection
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.frame = NSRect(x: 30, y: y, width: 60, height: 20)
        contentView.addSubview(modelLabel)
        
        modelPopup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: 250, height: 25))
        for model in TranscriptionModel.allCases {
            modelPopup.addItem(withTitle: model.displayName)
        }
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        contentView.addSubview(modelPopup)
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
        
        fillerWordsField = NSTextField(frame: NSRect(x: 30, y: y, width: 390, height: 50))
        fillerWordsField.placeholderString = "um, uh, like, you know..."
        fillerWordsField.usesSingleLineMode = false
        fillerWordsField.cell?.wraps = true
        fillerWordsField.cell?.isScrollable = false
        contentView.addSubview(fillerWordsField)
        y -= 50
        
        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 340, y: 15, width: 80, height: 32)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
        
        self.contentView = contentView
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
        
        // Model selection
        let savedModel = defaults.string(forKey: "selectedModel") ?? TranscriptionModel.defaultModel.rawValue
        if let model = TranscriptionModel(rawValue: savedModel),
           let index = TranscriptionModel.allCases.firstIndex(of: model) {
            modelPopup.selectItem(at: index)
        }
        
        // Filler words
        let fillerWords = defaults.stringArray(forKey: "fillerWords") ?? Array(TextFormatter.defaultFillerWords)
        fillerWordsField.stringValue = fillerWords.joined(separator: ", ")
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
        let index = modelPopup.indexOfSelectedItem
        guard index >= 0, index < TranscriptionModel.allCases.count else { return }
        let model = TranscriptionModel.allCases[index]
        UserDefaults.standard.set(model.rawValue, forKey: "selectedModel")
        modelManager.selectedModel = model
        logInfo("Model changed to: \(model.displayName)")
    }
    
    @objc private func saveSettings() {
        // Save filler words
        let fillerWords = fillerWordsField.stringValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(fillerWords, forKey: "fillerWords")
        
        logInfo("Settings saved. Filler words: \(fillerWords)")
        close()
    }
}
