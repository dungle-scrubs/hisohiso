import Cocoa

/// Model preferences tab: transcription model selection, download, filler words.
final class ModelPreferencesTab: NSView {
    private var modelPopup: NSPopUpButton!
    private var downloadButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var fillerWordsField: NSTextField!
    private let modelManager: ModelManager

    /// - Parameter modelManager: Manager for model downloads and selection.
    init(modelManager: ModelManager) {
        self.modelManager = modelManager
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 340))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        var y = 260

        let modelLabel = NSTextField(labelWithString: "Transcription Model:")
        modelLabel.frame = NSRect(x: 20, y: y, width: 140, height: 20)
        addSubview(modelLabel)

        modelPopup = NSPopUpButton(frame: NSRect(x: 170, y: y - 2, width: 260, height: 25))
        setupModelPopup()
        addSubview(modelPopup)
        y -= 35

        downloadButton = NSButton(title: "Download Model", target: self, action: #selector(downloadModel))
        downloadButton.bezelStyle = .rounded
        downloadButton.frame = NSRect(x: 170, y: y, width: 120, height: 25)
        addSubview(downloadButton)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 300, y: y + 3, width: 130, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isHidden = true
        addSubview(progressIndicator)
        y -= 25

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 170, y: y, width: 260, height: 20)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)
        y -= 40

        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        addSubview(separator)
        y -= 20

        let fillerLabel = NSTextField(labelWithString: "Filler Words to Remove:")
        fillerLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        addSubview(fillerLabel)
        y -= 60

        fillerWordsField = NSTextField(frame: NSRect(x: 20, y: y, width: 420, height: 50))
        fillerWordsField.placeholderString = "um, uh, like, you know..."
        fillerWordsField.usesSingleLineMode = false
        fillerWordsField.cell?.wraps = true
        fillerWordsField.cell?.isScrollable = false
        addSubview(fillerWordsField)
        y -= 30

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveFillerWords))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 360, y: y, width: 80, height: 25)
        addSubview(saveButton)
    }

    private func setupModelPopup() {
        let menu = NSMenu()
        let parakeetHeader = NSMenuItem(title: "── Parakeet (Best Accuracy) ──", action: nil, keyEquivalent: "")
        parakeetHeader.isEnabled = false
        menu.addItem(parakeetHeader)
        for model in TranscriptionModel.parakeetModels {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model
            menu.addItem(item)
        }
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

    /// Load current settings into controls.
    func loadSettings() {
        selectModelInPopup(modelManager.selectedModel)
        let fillerWords = UserDefaults.standard.stringArray(for: .fillerWords) ?? Array(TextFormatter.defaultFillerWords)
        fillerWordsField.stringValue = fillerWords.joined(separator: ", ")
        updateModelUI()
    }

    // MARK: - Helpers

    private func selectModelInPopup(_ model: TranscriptionModel) {
        guard let menu = modelPopup.menu else { return }
        for (index, item) in menu.items.enumerated() {
            if let m = item.representedObject as? TranscriptionModel, m == model {
                modelPopup.selectItem(at: index)
                return
            }
        }
    }

    private func getSelectedModel() -> TranscriptionModel? {
        modelPopup.selectedItem?.representedObject as? TranscriptionModel
    }

    private func updateModelUI() {
        guard let model = getSelectedModel() else { return }
        Task { @MainActor in
            let isDownloaded = await modelManager.isModelDownloaded(model)
            statusLabel.stringValue = isDownloaded ? "✓ Downloaded and ready" : "Not downloaded"
            statusLabel.textColor = isDownloaded ? .systemGreen : .secondaryLabelColor
            downloadButton.title = isDownloaded ? "Re-download" : "Download"
            downloadButton.isEnabled = !modelManager.isDownloading
            progressIndicator.isHidden = !modelManager.isDownloading
        }
    }

    // MARK: - Actions

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
        let words = fillerWordsField.stringValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(words, forKey: SettingsKey.fillerWords.rawValue)
        logInfo("Filler words saved: \(words)")
    }
}
