import Cocoa
import Combine
import SwiftUI

/// Main application entry point
@main
struct HisohisoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app - no main window
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPill: FloatingPillWindow?
    private var dictationController: DictationController?
    private var modelManager: ModelManager?
    private var hotkeyManager: HotkeyManager?
    private var wakeWordManager: WakeWordManager?
    private var stateObserver: AnyCancellable?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var historyPalette: HistoryPaletteWindow?
    private var historyHotkeyMonitor: HistoryHotkeyMonitor?

    /// UserDefaults key for tracking first launch
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        logInfo("Hisohiso starting...")
        logInfo("Log file: \(Logger.shared.logFilePath)")

        // Handle CLI arguments (e.g., --history from RustyBar click)
        handleLaunchArguments()

        modelManager = ModelManager()
        setupStatusItem()
        setupFloatingPill()
        setupHistoryPalette()
        setupHistoryHotkey()

        // Check if first launch
        if !UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) {
            showOnboarding()
        } else {
            setupDictationController()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictationController?.shutdown()
        historyHotkeyMonitor?.stop()
        hotkeyManager?.stop()
        logInfo("Hisohiso shutting down")
    }

    /// Handle reopen (e.g., clicking dock icon or `open -a Hisohiso`)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    /// Handle Apple Events (for `open -a Hisohiso --args --history`)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "hisohiso" {
                handleURL(url)
            }
        }
    }

    private func handleURL(_ url: URL) {
        logInfo("Handling URL: \(url)")
        if url.host == "history" {
            toggleHistoryPalette()
        }
    }

    private func handleLaunchArguments() {
        let args = CommandLine.arguments

        if args.contains("--history") {
            logInfo("Launched with --history flag, showing history palette")
            // Delay slightly to ensure app is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleHistoryPalette()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use text as fallback if SF Symbol fails
            if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hisohiso") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
            } else {
                // Fallback to text
                button.title = "🎤"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        logInfo("Status item created")
    }

    private func setupFloatingPill() {
        floatingPill = FloatingPillWindow()
        logInfo("Floating pill created")
    }

    private func setupHistoryPalette() {
        historyPalette = HistoryPaletteWindow()
        historyPalette?.onSelect = { [weak self] record in
            self?.handleHistorySelection(record)
        }
        logInfo("History palette created")
    }

    private func setupHistoryHotkey() {
        historyHotkeyMonitor = HistoryHotkeyMonitor()
        historyHotkeyMonitor?.onHotkey = { [weak self] in
            self?.toggleHistoryPalette()
        }
        historyHotkeyMonitor?.start()
        logInfo("History hotkey monitor started (⌃⌥Space)")
    }

    private func toggleHistoryPalette() {
        guard let palette = historyPalette else { return }

        if palette.isVisible {
            palette.dismiss()
        } else {
            palette.showPalette()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func handleHistorySelection(_ record: TranscriptionRecord) {
        logInfo("History item selected: \(record.text.prefix(50))...")

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)

        // Also insert at cursor if possible
        let textInserter = TextInserter()
        do {
            try textInserter.insert(record.text)
            logInfo("Inserted history text at cursor")
        } catch {
            logWarning("Could not insert at cursor, copied to clipboard: \(error)")
            // Show notification that text was copied
            showCopiedNotification()
        }
    }

    private func showCopiedNotification() {
        // Brief visual feedback that text was copied
        let alert = NSAlert()
        alert.messageText = "Copied to Clipboard"
        alert.informativeText = "The text has been copied. Press ⌘V to paste."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        // Auto-dismiss after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.stopModal()
        }

        alert.runModal()
    }

    private func setupDictationController() {
        guard let modelManager else { return }

        // Setup alternative hotkey manager
        hotkeyManager = HotkeyManager()

        dictationController = DictationController(modelManager: modelManager, hotkeyManager: hotkeyManager)

        // Observe state changes to update floating pill
        if let controller = dictationController {
            stateObserver = controller.stateManager.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.updateFloatingPill(for: state)
                    // Resume wake word listening and monitoring when idle
                    if case .idle = state {
                        if self?.wakeWordManager?.isEnabled == true {
                            self?.dictationController?.audioRecorder.resumeMonitoring()
                            self?.wakeWordManager?.resumeListening()
                        }
                    }
                }

            // Forward audio levels to floating pill
            controller.onAudioLevels = { [weak self] levels in
                self?.floatingPill?.updateAudioLevels(levels)
            }
        }

        // Initialize in background
        Task { [weak self] in
            do {
                try await self?.dictationController?.initialize()
                // Setup wake word after dictation is ready
                await self?.setupWakeWord()
            } catch {
                logError("Failed to initialize dictation controller: \(error)")
                self?.showInitializationError(error)
            }
        }
    }

    private func setupWakeWord() async {
        logInfo("Setting up wake word manager...")
        wakeWordManager = WakeWordManager()
        
        // Connect AudioRecorder's monitoring to WakeWordManager
        dictationController?.audioRecorder.onMonitoringSamples = { [weak self] samples, sampleRate in
            self?.wakeWordManager?.processAudioSamples(samples, sampleRate: sampleRate)
        }
        
        // When wake word detected, start recording
        wakeWordManager?.onWakeWordDetected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.dictationController?.stateManager.isIdle == true else { return }
                
                logInfo("Wake word triggered recording")
                // Pause monitoring and wake word listening while recording
                self.dictationController?.audioRecorder.pauseMonitoring()
                self.wakeWordManager?.pauseListening()
                // Start recording with auto-stop on silence
                await self.dictationController?.startRecording(fromWakeWord: true)
            }
        }
        
        // Initialize Whisper tiny for wake word
        if wakeWordManager?.isEnabled == true {
            do {
                try await wakeWordManager?.initialize()
            } catch {
                logError("Failed to initialize wake word: \(error)")
            }
        }
        
        // Start monitoring if enabled
        logInfo("Wake word enabled: \(wakeWordManager?.isEnabled ?? false)")
        if wakeWordManager?.isEnabled == true {
            do {
                try dictationController?.audioRecorder.startMonitoring()
                wakeWordManager?.startListening()
                logInfo("Wake word monitoring started")
            } catch {
                logError("Failed to start wake word monitoring: \(error)")
            }
        }
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            forName: .wakeWordSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.wakeWordManager?.isEnabled == true {
                    do {
                        try await self.wakeWordManager?.initialize()
                        try self.dictationController?.audioRecorder.startMonitoring()
                        self.wakeWordManager?.startListening()
                    } catch {
                        logError("Failed to start wake word: \(error)")
                    }
                } else {
                    self.wakeWordManager?.stopListening()
                    self.dictationController?.audioRecorder.stopMonitoring()
                }
            }
        }
    }

    private func updateFloatingPill(for state: RecordingState) {
        logInfo("updateFloatingPill called with state: \(state)")

        // Check if pill should be shown
        let showPill = RustyBarBridge.shared.shouldShowFloatingPill

        // Always show pill for errors (RustyBar can't show error details)
        let isError = { if case .error = state { return true } else { return false } }()

        if !showPill && !isError {
            // Hide pill
            floatingPill?.show(
                state: .idle,
                onDismiss: {},
                onRetry: {}
            )
            return
        }

        floatingPill?.show(
            state: state,
            onDismiss: { [weak self] in
                self?.dictationController?.stateManager.setIdle()
            },
            onRetry: { [weak self] in
                self?.dictationController?.stateManager.retry()
            }
        )
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            showPreferences()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Microphone submenu
        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let microphoneMenu = NSMenu()
        let devices = AudioRecorder.availableInputDevices()
        let currentDevice = dictationController?.audioRecorder.currentDevice() ?? .systemDefault

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = (device == currentDevice) ? .on : .off
            microphoneMenu.addItem(item)
        }
        microphoneItem.submenu = microphoneMenu
        menu.addItem(microphoneItem)

        // Transcription model submenu
        let modelItem = NSMenuItem(title: "Transcription Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let currentModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "parakeet-v2"
        let models = [
            ("Parakeet v2 (English)", "parakeet-v2"),
            ("Whisper Large v3 Turbo", "large-v3-turbo"),
            ("Whisper Small (English)", "small-en")
        ]
        for (name, id) in models {
            let item = NSMenuItem(title: name, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == currentModel) ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Test UI", action: #selector(testUI), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hisohiso", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so left-click works
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioInputDevice else { return }
        dictationController?.audioRecorder.setInputDevice(device)
        logInfo("Microphone selected: \(device.name)")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        UserDefaults.standard.set(modelId, forKey: "selectedModel")
        logInfo("Model selected: \(modelId)")
        // Reinitialize transcriber with new model would go here
    }
    
    @objc private func testUI() {
        logInfo("testUI called - showing pill")
        dictationController?.stateManager.setRecording()
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dictationController?.stateManager.setIdle()
        }
    }
    
    private func showOnboarding() {
        logInfo("Showing onboarding")
        onboardingWindow = OnboardingWindow { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: self.hasCompletedOnboardingKey)
            self.onboardingWindow = nil
            self.setupDictationController()
            logInfo("Onboarding completed")
        }
        
        if let window = onboardingWindow {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            logInfo("Onboarding window: frame=\(window.frame), isVisible=\(window.isVisible)")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        logInfo("Show preferences")

        guard let modelManager else { return }

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(modelManager: modelManager, hotkeyManager: hotkeyManager)
        }

        if let window = preferencesWindow {
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.makeMain()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showInitializationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Hisohiso Setup Required"

        // Provide specific instructions based on error type
        if let dictationError = error as? DictationError {
            switch dictationError {
            case .accessibilityPermissionDenied:
                alert.informativeText = """
                    Hisohiso needs Accessibility permission to capture the Globe key and insert text.

                    1. Click "Open System Settings"
                    2. Find Hisohiso in the list and enable it
                    3. If not in list, click + and add this app
                    4. Restart Hisohiso
                    """
            case .microphonePermissionDenied:
                alert.informativeText = """
                    Hisohiso needs Microphone permission to record audio for transcription.

                    Click "Open System Settings" and enable Microphone access.
                    """
            default:
                alert.informativeText = error.localizedDescription
            }
        } else {
            alert.informativeText = error.localizedDescription
        }

        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open directly to Accessibility settings
            if let dictationError = error as? DictationError {
                let urlString: String
                switch dictationError {
                case .accessibilityPermissionDenied:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                case .microphonePermissionDenied:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                default:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy"
                }
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}
