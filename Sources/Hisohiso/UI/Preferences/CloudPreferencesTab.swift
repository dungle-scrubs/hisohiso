import Cocoa

/// Cloud preferences tab: cloud fallback toggle, provider selection, API keys.
final class CloudPreferencesTab: NSView {
    private var cloudFallbackToggle: NSButton!
    private var cloudProviderPopup: NSPopUpButton!
    private var openAIKeyField: NSSecureTextField!
    private var groqKeyField: NSSecureTextField!
    private var openAIStatusLabel: NSTextField!
    private var groqStatusLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        var y = 260

        let description =
            NSTextField(
                wrappingLabelWithString: "Cloud transcription is optional. Local models are always tried first. Enable fallback to use cloud when local fails."
            )
        description.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        addSubview(description)
        y -= 60

        cloudFallbackToggle = NSButton(
            checkboxWithTitle: "Use cloud as fallback when local fails",
            target: self,
            action: #selector(cloudFallbackChanged)
        )
        cloudFallbackToggle.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        addSubview(cloudFallbackToggle)
        y -= 35

        let providerLabel = NSTextField(labelWithString: "Preferred Provider:")
        providerLabel.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        addSubview(providerLabel)

        cloudProviderPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 150, height: 25))
        for provider in CloudProviderType.allCases {
            cloudProviderPopup.addItem(withTitle: provider.displayName)
            cloudProviderPopup.lastItem?.representedObject = provider
        }
        cloudProviderPopup.target = self
        cloudProviderPopup.action = #selector(cloudProviderChanged)
        addSubview(cloudProviderPopup)
        y -= 40

        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        addSubview(separator)
        y -= 20

        let apiLabel = NSTextField(labelWithString: "API Keys")
        apiLabel.font = .boldSystemFont(ofSize: 12)
        apiLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        addSubview(apiLabel)
        y -= 30

        let openAILabel = NSTextField(labelWithString: "OpenAI:")
        openAILabel.frame = NSRect(x: 20, y: y, width: 60, height: 20)
        addSubview(openAILabel)

        openAIKeyField = NSSecureTextField(frame: NSRect(x: 90, y: y - 2, width: 280, height: 22))
        openAIKeyField.placeholderString = "sk-..."
        openAIKeyField.target = self
        openAIKeyField.action = #selector(openAIKeyChanged)
        addSubview(openAIKeyField)

        openAIStatusLabel = NSTextField(labelWithString: "")
        openAIStatusLabel.frame = NSRect(x: 380, y: y, width: 60, height: 20)
        openAIStatusLabel.font = .systemFont(ofSize: 11)
        addSubview(openAIStatusLabel)
        y -= 32

        let groqLabel = NSTextField(labelWithString: "Groq:")
        groqLabel.frame = NSRect(x: 20, y: y, width: 60, height: 20)
        addSubview(groqLabel)

        groqKeyField = NSSecureTextField(frame: NSRect(x: 90, y: y - 2, width: 280, height: 22))
        groqKeyField.placeholderString = "gsk_..."
        groqKeyField.target = self
        groqKeyField.action = #selector(groqKeyChanged)
        addSubview(groqKeyField)

        groqStatusLabel = NSTextField(labelWithString: "")
        groqStatusLabel.frame = NSRect(x: 380, y: y, width: 60, height: 20)
        groqStatusLabel.font = .systemFont(ofSize: 11)
        addSubview(groqStatusLabel)
    }

    /// Load current settings into controls.
    func loadSettings() {
        let settings = CloudFallbackSettings.load()
        cloudFallbackToggle.state = settings.enabled ? .on : .off
        for (index, item) in cloudProviderPopup.itemArray.enumerated() {
            if let provider = item.representedObject as? CloudProviderType, provider == settings.preferredProvider {
                cloudProviderPopup.selectItem(at: index)
                break
            }
        }
        updateKeyStatus()
    }

    private func updateKeyStatus() {
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

    @objc private func cloudFallbackChanged() {
        var settings = CloudFallbackSettings.load()
        settings.enabled = cloudFallbackToggle.state == .on
        settings.save()
    }

    @objc private func cloudProviderChanged() {
        guard let item = cloudProviderPopup.selectedItem,
              let provider = item.representedObject as? CloudProviderType else { return }
        var settings = CloudFallbackSettings.load()
        settings.preferredProvider = provider
        settings.save()
    }

    @objc private func openAIKeyChanged() {
        let key = openAIKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { _ = KeychainManager.shared.deleteAPIKey(.openAI) }
        else { _ = KeychainManager.shared.setAPIKey(key, type: .openAI) }
        openAIKeyField.stringValue = ""
        updateKeyStatus()
    }

    @objc private func groqKeyChanged() {
        let key = groqKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { _ = KeychainManager.shared.deleteAPIKey(.groq) }
        else { _ = KeychainManager.shared.setAPIKey(key, type: .groq) }
        groqKeyField.stringValue = ""
        updateKeyStatus()
    }
}
