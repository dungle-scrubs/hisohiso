import Cocoa

/// Preferences window coordinator — creates and manages tabbed preferences.
final class PreferencesWindow: NSWindow {
    private let generalTab: GeneralPreferencesTab
    private let hotkeyTab: HotkeyPreferencesTab
    private let modelTab: ModelPreferencesTab
    private let cloudTab: CloudPreferencesTab
    private let voiceTab: VoicePreferencesTab
    private let wakeWordTab: WakeWordPreferencesTab

    /// Create the preferences window.
    /// - Parameters:
    ///   - modelManager: Manager for model downloads and selection.
    ///   - hotkeyManager: Manager for alternative hotkey configuration.
    init(modelManager: ModelManager, hotkeyManager: HotkeyManager? = nil) {
        let tabFrame = NSRect(x: 0, y: 0, width: 460, height: 340)
        generalTab = GeneralPreferencesTab(frame: tabFrame)
        hotkeyTab = HotkeyPreferencesTab(hotkeyManager: hotkeyManager)
        modelTab = ModelPreferencesTab(modelManager: modelManager)
        cloudTab = CloudPreferencesTab(frame: tabFrame)
        voiceTab = VoicePreferencesTab(frame: tabFrame)
        wakeWordTab = WakeWordPreferencesTab(frame: tabFrame)

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

    // MARK: - Setup

    private func setupTabView() {
        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))

        let tabs: [(String, String, NSView)] = [
            ("general", "General", generalTab),
            ("hotkey", "Hotkey", hotkeyTab),
            ("model", "Model", modelTab),
            ("cloud", "Cloud", cloudTab),
            ("voice", "Voice", voiceTab),
            ("wakeword", "Wake Word", wakeWordTab)
        ]

        for (id, label, view) in tabs {
            let item = NSTabViewItem(identifier: id)
            item.label = label
            item.view = view
            tabView.addTabViewItem(item)
        }

        contentView = tabView
    }

    private func loadSettings() {
        generalTab.loadSettings()
        modelTab.loadSettings()
        cloudTab.loadSettings()
        voiceTab.loadSettings()
    }

    // MARK: - Window Lifecycle

    override func close() {
        voiceTab.cancelEnrollment()
        NSApp.setActivationPolicy(.accessory)
        super.close()
    }
}
