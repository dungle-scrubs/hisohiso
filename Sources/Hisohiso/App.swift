import Cocoa
import Combine
import Darwin

@main
enum HisohisoMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPill: FloatingPillWindow?
    var dictationController: DictationController?
    var modelManager: ModelManager?
    var modelSelectionController: ModelSelectionController?
    private var hotkeyManager: HotkeyManager?
    private var wakeWordManager: WakeWordManager?
    private var stateObserver: AnyCancellable?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var historyPalette: HistoryPaletteWindow?
    private var historyHotkeyMonitor: HistoryHotkeyMonitor?
    private var wakeWordSettingsObserver: NSObjectProtocol?
    private var microphoneSelectionObserver: NSObjectProtocol?
    private var showHistoryOnLaunch = false
    var controlServer: ControlServer?
    private let lifecycleCoordinator = AppLifecycleCoordinator()
    let preferences = AppPreferences.shared
    var singleInstanceLock: SingleInstanceLock?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Handle launch arguments before initializing UI.
        if handleLaunchArguments() {
            return
        }

        if shouldDeferToLaunchdInstance() {
            kickstartLaunchdInstance()
            NSApp.terminate(nil)
            return
        }

        guard acquireSingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        _ = lifecycleCoordinator.prepareLaunch()

        modelManager = ModelManager()
        if let modelManager {
            modelSelectionController = ModelSelectionController(modelManager: modelManager)
        }
        setupStatusItem()
        setupFloatingPill()
        setupHistoryPalette()
        setupHistoryHotkey()
        setupSettingsObservers()
        startControlServer()
        handleDeferredLaunchActions()

        // Check if first launch
        if !preferences.hasCompletedOnboarding {
            showOnboarding()
        } else {
            setupDictationController()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
        dictationController?.shutdown()
        historyHotkeyMonitor?.stop()
        hotkeyManager?.stop()

        if let observer = wakeWordSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = microphoneSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        lifecycleCoordinator.finishTermination()
    }

    /// Handle reopen (e.g., clicking dock icon or `open -a Hisohiso`)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    /// Handle Apple Events (for `open -a Hisohiso --args --history`)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "hisohiso" {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        logInfo("Handling URL: \(url)")
        if url.host == "history" {
            toggleHistoryPalette()
        }
    }

    /// Parse launch arguments and optionally run in headless CLI mode.
    /// - Returns: `true` if launch handling is complete and app startup should stop.
    private func handleLaunchArguments() -> Bool {
        let arguments = CommandLine.arguments
        switch CLIArguments.parse(arguments) {
        case let .success(mode):
            switch mode {
            case let .app(showHistoryOnLaunch):
                self.showHistoryOnLaunch = showHistoryOnLaunch
                return false
            case let .cli(command):
                Task { [weak self] in
                    let exitCode = await self?.runCLICommand(command) ?? 1
                    exit(exitCode)
                }
                return true
            }
        case let .failure(error):
            writeCLIError(error.localizedDescription)
            writeCLIError(CLIArguments.usage(executableName: CLIArguments.executableName(from: arguments)))
            exit(2)
        }
    }

    /// Run deferred launch actions after UI objects are initialized.
    private func handleDeferredLaunchActions() {
        guard showHistoryOnLaunch else { return }
        logInfo("Launched with --history flag, showing history palette")
        // Delay slightly to ensure app is fully initialized.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.toggleHistoryPalette()
        }
    }

    private func setupSettingsObservers() {
        let center = NotificationCenter.default

        microphoneSelectionObserver = center.addObserver(
            forName: .audioInputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.applySelectedMicrophonePreference()
            }
        }
    }

    private func applySelectedMicrophonePreference() {
        let selectedUID = preferences.selectedAudioDeviceUID
        let selectedDevice = AudioRecorder.availableInputDevices().first {
            $0.uid == selectedUID
        } ?? .systemDefault

        dictationController?.setInputDevice(selectedDevice)
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

    /// Reusable toast for clipboard notifications.
    private let toast = ToastWindow()

    private func showCopiedNotification() {
        toast.show("✓ Copied to clipboard")
    }

    private func setupDictationController() {
        guard let modelManager else { return }

        // Setup alternative hotkey manager
        hotkeyManager = HotkeyManager()

        dictationController = DictationController(modelManager: modelManager, hotkeyManager: hotkeyManager)
        if let dictationController {
            modelSelectionController?.attachReloader(dictationController)
        }
        applySelectedMicrophonePreference()

        // Observe state changes to update floating pill
        if let controller = dictationController {
            stateObserver = controller.observeRecordingState { [weak self] state in
                self?.updateFloatingPill(for: state)
                // Resume wake word listening and monitoring when idle
                if case .idle = state {
                    if let modelSelectionController = self?.modelSelectionController {
                        Task { @MainActor in
                            await modelSelectionController.applyPendingReloadIfPossible()
                        }
                    }

                    if self?.wakeWordManager?.isEnabled == true {
                        self?.dictationController?.resumeWakeWordMonitoring()
                        self?.wakeWordManager?.resumeListening()
                    }
                }
            }

            // Forward audio levels to the floating pill and any external waveform display
            controller.onAudioLevels = { [weak self] levels in
                self?.floatingPill?.updateAudioLevels(levels)
                WaveformBridge.shared.sendLevels(levels)
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
        dictationController?.setMonitoringSamplesHandler { [weak self] samples, sampleRate in
            self?.wakeWordManager?.processAudioSamples(samples, sampleRate: sampleRate)
        }

        // When wake word detected, start recording
        wakeWordManager?.onWakeWordDetected = { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard dictationController?.isIdle == true else { return }

                logInfo("Wake word triggered recording")
                // Pause monitoring and wake word listening while recording
                dictationController?.pauseWakeWordMonitoring()
                wakeWordManager?.pauseListening()
                // Start recording with auto-stop on silence
                await dictationController?.startRecording(fromWakeWord: true)
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
                try dictationController?.startWakeWordMonitoring()
                wakeWordManager?.startListening()
                logInfo("Wake word monitoring started")
            } catch {
                logError("Failed to start wake word monitoring: \(error)")
            }
        }

        // Listen for settings changes
        if let observer = wakeWordSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        wakeWordSettingsObserver = NotificationCenter.default.addObserver(
            forName: .wakeWordSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                let isEnabled = preferences.wakeWordEnabled
                wakeWordManager?.isEnabled = isEnabled

                if isEnabled {
                    do {
                        try await wakeWordManager?.initialize()
                        try dictationController?.startWakeWordMonitoring()
                        wakeWordManager?.startListening()
                    } catch {
                        logError("Failed to start wake word: \(error)")
                    }
                } else {
                    wakeWordManager?.stopListening()
                    dictationController?.stopWakeWordMonitoring()
                }
            }
        }
    }

    private func updateFloatingPill(for state: RecordingState) {
        logInfo("updateFloatingPill called with state: \(state)")

        // Re-check whether an external waveform display is listening (it may have
        // started or stopped since the last state change).
        WaveformBridge.shared.checkAvailability()

        // Show the pill when the user enabled it, or as a fallback when no external
        // waveform display is connected.
        let showPill = AppPreferences.shared.showFloatingPill || !WaveformBridge.shared.isAvailable

        // Always show the pill for errors so the message is visible.
        let isError = if case .error = state { true } else { false }

        if !showPill, !isError {
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
                self?.dictationController?.dismissCurrentState()
            },
            onRetry: { [weak self] in
                self?.dictationController?.retryCurrentState()
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
        let snapshot = StatusMenuSnapshot(
            microphones: AudioRecorder.availableInputDevices(),
            currentMicrophone: dictationController?.currentInputDevice() ?? .systemDefault,
            currentModel: modelSelectionController?.selectedModel ?? .defaultModel
        )
        let menu = StatusMenuCoordinator(builder: StatusMenuBuilder(
            target: self,
            selectMicrophone: #selector(selectMicrophone(_:)),
            selectModel: #selector(selectModel(_:)),
            showPreferences: #selector(showPreferences)
        )).menu(snapshot: snapshot)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so left-click works
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioInputDevice else { return }
        preferences.selectAudioDevice(device)
        dictationController?.setInputDevice(device)
        logInfo("Microphone selected: \(device.name)")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let model = TranscriptionModel(rawValue: rawValue),
              let modelSelectionController
        else {
            return
        }

        Task { @MainActor in
            do {
                try await modelSelectionController.requestSelection(model)
                logInfo("Model selected: \(model.rawValue)")
            } catch {
                logError("Model selection failed: \(error)")
            }
        }
    }

    #if DEBUG
    @objc private func testUI() {
        logInfo("testUI called - showing pill")
        updateFloatingPill(for: .recording)

        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updateFloatingPill(for: .idle)
        }
    }
    #endif

    private func showOnboarding() {
        logInfo("Showing onboarding")
        onboardingWindow = OnboardingWindow { [weak self] in
            guard let self else { return }
            preferences.hasCompletedOnboarding = true
            onboardingWindow = nil
            setupDictationController()
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

        guard let modelManager, let modelSelectionController else { return }

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(
                modelManager: modelManager,
                modelSelectionController: modelSelectionController,
                hotkeyManager: hotkeyManager,
                historyHotkeyMonitor: historyHotkeyMonitor
            )
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
}
