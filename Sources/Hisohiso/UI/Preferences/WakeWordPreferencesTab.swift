import Cocoa

/// Wake word preferences tab: enable/disable, wake phrase configuration.
final class WakeWordPreferencesTab: NSView {
    private var wakeWordToggle: NSButton!
    private var wakePhraseField: NSTextField!
    private var statusLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        loadSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        var y = 290

        let header = NSTextField(labelWithString: "Wake Word Detection")
        header.font = .boldSystemFont(ofSize: 12)
        header.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        addSubview(header)
        y -= 30

        wakeWordToggle = NSButton(checkboxWithTitle: "Enable wake word detection", target: self, action: #selector(toggleChanged))
        wakeWordToggle.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        addSubview(wakeWordToggle)
        y -= 25

        let desc = NSTextField(wrappingLabelWithString: "Say your wake phrase to start recording without pressing any keys. Uses Whisper tiny for continuous listening.")
        desc.frame = NSRect(x: 40, y: y - 20, width: 380, height: 40)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        addSubview(desc)
        y -= 60

        let phraseLabel = NSTextField(labelWithString: "Wake Phrase:")
        phraseLabel.frame = NSRect(x: 20, y: y, width: 100, height: 20)
        addSubview(phraseLabel)

        wakePhraseField = NSTextField(frame: NSRect(x: 130, y: y, width: 200, height: 22))
        wakePhraseField.placeholderString = "hey hisohiso"
        wakePhraseField.target = self
        wakePhraseField.action = #selector(phraseChanged)
        addSubview(wakePhraseField)
        y -= 30

        let examples = NSTextField(wrappingLabelWithString: "Examples: \"hey computer\", \"hey kevin\", \"dictate\"")
        examples.frame = NSRect(x: 130, y: y, width: 300, height: 20)
        examples.font = .systemFont(ofSize: 11)
        examples.textColor = .tertiaryLabelColor
        addSubview(examples)
        y -= 40

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)
        y -= 40

        let warning = NSTextField(wrappingLabelWithString: "⚠️ Wake word detection keeps the microphone active and uses some CPU. This may impact battery life on laptops.")
        warning.frame = NSRect(x: 20, y: y - 20, width: 400, height: 40)
        warning.font = .systemFont(ofSize: 11)
        warning.textColor = .systemOrange
        addSubview(warning)
    }

    private func loadSettings() {
        wakeWordToggle.state = UserDefaults.standard.bool(forKey: "wakeWordEnabled") ? .on : .off
        wakePhraseField.stringValue = UserDefaults.standard.string(forKey: "wakePhrase") ?? "hey hisohiso"
        updateStatus()
    }

    private func updateStatus() {
        if wakeWordToggle.state == .on {
            statusLabel.stringValue = "Wake word detection is active. Say \"\(wakePhraseField.stringValue)\" to start recording."
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "Wake word detection is disabled."
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func toggleChanged() {
        UserDefaults.standard.set(wakeWordToggle.state == .on, forKey: "wakeWordEnabled")
        updateStatus()
        NotificationCenter.default.post(name: .wakeWordSettingsChanged, object: nil)
    }

    @objc private func phraseChanged() {
        let phrase = wakePhraseField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(phrase, forKey: "wakePhrase")
        updateStatus()
        NotificationCenter.default.post(name: .wakeWordSettingsChanged, object: nil)
    }
}
