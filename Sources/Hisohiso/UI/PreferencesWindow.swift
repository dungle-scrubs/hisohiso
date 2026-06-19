import Cocoa

/// Preferences window coordinator — creates and manages tabbed preferences.
final class PreferencesWindow: NSWindow {
    private enum PreferencesTab: Int, CaseIterable {
        case general
        case hotkey
        case model
        case cloud
        case voice
        case wakeWord

        var label: String {
            switch self {
            case .general: "General"
            case .hotkey: "Hotkey"
            case .model: "Model"
            case .cloud: "Cloud"
            case .voice: "Voice"
            case .wakeWord: "Wake Word"
            }
        }
    }

    private let generalTab: GeneralPreferencesTab
    private let hotkeyTab: HotkeyPreferencesTab
    private let modelTab: ModelPreferencesTab
    private let cloudTab: CloudPreferencesTab
    private let voiceTab: VoicePreferencesTab
    private let wakeWordTab: WakeWordPreferencesTab
    private let tabControl: NSSegmentedControl
    private let tabContentView: NSView

    /// Create the preferences window.
    /// - Parameters:
    ///   - modelManager: Manager for model downloads and selection.
    ///   - hotkeyManager: Manager for alternative hotkey configuration.
    ///   - historyHotkeyMonitor: Monitor for history palette hotkey configuration.
    init(
        modelManager: ModelManager,
        modelSelectionController: ModelSelectionController? = nil,
        hotkeyManager: HotkeyManager? = nil,
        historyHotkeyMonitor: HistoryHotkeyMonitor? = nil
    ) {
        let tabFrame = NSRect(x: 0, y: 0, width: 460, height: 340)
        generalTab = GeneralPreferencesTab(frame: tabFrame)
        hotkeyTab = HotkeyPreferencesTab(hotkeyManager: hotkeyManager, historyHotkeyMonitor: historyHotkeyMonitor)
        modelTab = ModelPreferencesTab(
            modelManager: modelManager,
            modelSelectionController: modelSelectionController ?? ModelSelectionController(modelManager: modelManager)
        )
        cloudTab = CloudPreferencesTab(frame: tabFrame)
        voiceTab = VoicePreferencesTab(frame: tabFrame)
        wakeWordTab = WakeWordPreferencesTab(frame: tabFrame)
        tabControl = NSSegmentedControl(
            labels: PreferencesTab.allCases.map(\.label),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        tabContentView = NSView(frame: tabFrame)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Hisohiso Preferences"
        isReleasedWhenClosed = false
        center()

        setupContentView()
        loadSettings()
        selectTab(.general)
    }

    // MARK: - Setup

    private func setupContentView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        rootView.autoresizingMask = [.width, .height]

        tabControl.frame = NSRect(x: 20, y: 354, width: 440, height: 26)
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.selectedSegment = PreferencesTab.general.rawValue
        tabControl.autoresizingMask = [.width, .minYMargin]
        rootView.addSubview(tabControl)

        tabContentView.frame = NSRect(x: 10, y: 10, width: 460, height: 330)
        tabContentView.autoresizingMask = [.width, .height]
        rootView.addSubview(tabContentView)

        contentView = rootView
    }

    private func view(for tab: PreferencesTab) -> NSView {
        switch tab {
        case .general: generalTab
        case .hotkey: hotkeyTab
        case .model: modelTab
        case .cloud: cloudTab
        case .voice: voiceTab
        case .wakeWord: wakeWordTab
        }
    }

    private func loadSettings() {
        generalTab.loadSettings()
        modelTab.loadSettings()
        cloudTab.loadSettings()
        voiceTab.loadSettings()
    }

    private func selectTab(_ tab: PreferencesTab) {
        tabControl.selectedSegment = tab.rawValue
        tabContentView.subviews.forEach { $0.removeFromSuperview() }

        let selectedView = view(for: tab)
        selectedView.frame = tabContentView.bounds
        selectedView.autoresizingMask = [.width, .height]
        tabContentView.addSubview(selectedView)
    }

    @objc private func tabChanged() {
        guard let tab = PreferencesTab(rawValue: tabControl.selectedSegment) else { return }
        selectTab(tab)
    }

    // MARK: - Window Lifecycle

    override func close() {
        voiceTab.cancelEnrollment()
        NSApp.setActivationPolicy(.accessory)
        super.close()
    }
}
