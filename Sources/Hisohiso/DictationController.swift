import Cocoa
import Combine
import Foundation

/// Coordinates the dictation flow: Globe key → recording → transcription → text insertion
@MainActor
final class DictationController: ObservableObject {
    private let globeMonitor = GlobeKeyMonitor()
    let audioRecorder = AudioRecorder()
    private let audioKitRecorder = AudioKitRecorder()
    let transcriber: TranscribingService
    let voiceVerifier: VoiceVerifying

    /// Whether to use AudioKit for recording (with noise handling)
    var useAudioKit: Bool {
        get { UserDefaults.standard.bool(for: .useAudioKit) }
        set { UserDefaults.standard.set(newValue, for: .useAudioKit) }
    }

    /// The active recorder, selected by the `useAudioKit` preference.
    var activeRecorder: AudioRecording {
        useAudioKit ? audioKitRecorder : audioRecorder
    }

    let textInserter = TextInserter()
    let textFormatter = TextFormatter()
    let audioFeedback = AudioFeedback()
    let mediaPlaybackCoordinator: MediaPlaybackCoordinator
    let modelManager: ModelManager
    private let hotkeyManager: HotkeyManager?
    let historyStore = HistoryStore.shared
    let waveformBridge = WaveformBridge.shared

    @Published private(set) var stateManager = RecordingStateManager()

    /// Track recording start time for duration calculation
    var recordingStartTime: Date?

    lazy var audioLevelPublisher = AudioLevelPublisher(
        sampleProvider: { [weak self] in self?.activeRecorder.getRecentSamples(count: 1600) ?? [] },
        levelSink: { [weak self] levels in self?.onAudioLevels?(levels) },
        autoStop: { [weak self] in
            Task { @MainActor [weak self] in await self?.stopRecordingAndTranscribe() }
        }
    )

    /// Callback for audio level updates (for UI waveform)
    var onAudioLevels: (([UInt8]) -> Void)?

    /// Monitor for escape key to cancel recording
    private var escapeMonitor: Any?

    /// Whether current recording was triggered by wake word (auto-stop on silence)
    private var isWakeWordTriggered = false

    private var isInitialized = false

    init(
        modelManager: ModelManager,
        hotkeyManager: HotkeyManager? = nil,
        mediaPlaybackCoordinator: MediaPlaybackCoordinator = MediaPlaybackCoordinator(),
        transcriber: TranscribingService = Transcriber(),
        voiceVerifier: VoiceVerifying = VoiceVerifier.shared
    ) {
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager
        self.mediaPlaybackCoordinator = mediaPlaybackCoordinator
        self.transcriber = transcriber
        self.voiceVerifier = voiceVerifier
        setupCallbacks()
    }

    var recordingState: RecordingState {
        stateManager.state
    }

    var isIdle: Bool {
        stateManager.isIdle
    }

    var isRecording: Bool {
        stateManager.isRecording
    }

    var isModelReloadAllowed: Bool {
        stateManager.isIdle
    }

    func observeRecordingState(_ handler: @escaping (RecordingState) -> Void) -> AnyCancellable {
        stateManager.$state
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }

    func setInputDevice(_ device: AudioInputDevice) {
        audioRecorder.setInputDevice(device)
    }

    func currentInputDevice() -> AudioInputDevice {
        audioRecorder.currentDevice()
    }

    func setMonitoringSamplesHandler(_ handler: @escaping (_ samples: [Float], _ sampleRate: Double) -> Void) {
        audioRecorder.onMonitoringSamples = handler
    }

    func startWakeWordMonitoring() throws {
        try audioRecorder.startMonitoring()
    }

    func stopWakeWordMonitoring() {
        audioRecorder.stopMonitoring()
    }

    func pauseWakeWordMonitoring() {
        audioRecorder.pauseMonitoring()
    }

    func resumeWakeWordMonitoring() {
        audioRecorder.resumeMonitoring()
    }

    func dismissCurrentState() {
        stateManager.setIdle()
    }

    func retryCurrentState() {
        stateManager.retry()
    }

    /// Initialize the controller and start monitoring
    func initialize() async throws {
        guard !isInitialized else { return }

        logInfo("Initializing DictationController...")

        // Request microphone permission
        let hasMicPermission = await AudioRecorder.requestPermission()
        if !hasMicPermission {
            throw DictationError.microphonePermissionDenied
        }

        // Check accessibility permission - but don't block on it
        // The event tap creation will fail if we truly don't have permission
        let hasAccessibility = GlobeKeyMonitor.checkAccessibilityPermission(prompt: true)
        logInfo("Accessibility permission check: \(hasAccessibility) (will try event tap anyway)")

        // Initialize transcriber with selected model
        try await transcriber.initialize(model: modelManager.selectedModel)

        // Start Globe key monitoring
        guard globeMonitor.start() else {
            throw DictationError.eventTapFailed
        }

        // Start alternative hotkey monitoring (if configured)
        hotkeyManager?.start()

        isInitialized = true
        logInfo("DictationController initialized")
    }

    /// Stop the controller
    func shutdown() {
        globeMonitor.stop()
        hotkeyManager?.stop()
        stopEscapeMonitor()
        if stateManager.isRecording {
            activeRecorder.cancelRecording()
            mediaPlaybackCoordinator.resumeAfterRecording()
        }
        stateManager.setIdle()
        logInfo("DictationController shutdown")
    }

    private func setupCallbacks() {
        logInfo("Setting up callbacks...")

        // Tap: toggle recording on/off
        globeMonitor.onGlobeTap = { [weak self] in
            guard let self else {
                logWarning("onGlobeTap: self is nil")
                return
            }
            logInfo("Globe tap received, calling toggleRecording")
            Task { await self.toggleRecording() }
        }

        // Hold: start recording, or stop if already recording from tap
        globeMonitor.onGlobeHoldStart = { [weak self] in
            guard let self else {
                logWarning("onGlobeHoldStart: self is nil")
                return
            }
            logInfo("Globe hold start received")
            // If already recording (from a tap), stop immediately
            if stateManager.isRecording {
                logInfo("Hold started while recording - stopping immediately")
                Task { await self.stopRecordingAndTranscribe() }
                return
            }
            Task { await self.startRecording() }
        }

        // Release after hold: stop recording (only if still recording)
        globeMonitor.onGlobeHoldEnd = { [weak self] in
            guard let self else {
                logWarning("onGlobeHoldEnd: self is nil")
                return
            }
            // Only stop if still recording (might have been stopped by hold-start)
            guard stateManager.isRecording else { return }
            Task { await self.stopRecordingAndTranscribe() }
        }

        // Alternative hotkey: hold to record
        hotkeyManager?.onHotkeyDown = { [weak self] in
            guard let self else { return }
            Task { await self.startRecording() }
        }

        hotkeyManager?.onHotkeyUp = { [weak self] in
            guard let self else { return }
            Task { await self.stopRecordingAndTranscribe() }
        }

        // Handle retry from error state
        stateManager.onRetry = { [weak self] in
            Task { @MainActor [weak self] in
                self?.stateManager.setIdle()
            }
        }
    }

    private func toggleRecording() async {
        logInfo("toggleRecording called (state: \(stateManager.state))")
        if stateManager.isIdle {
            logInfo("State is idle, starting recording")
            await startRecording()
        } else if stateManager.isRecording {
            await stopRecordingAndTranscribe()
        }
        // Ignore if transcribing or in error state
    }

    /// Reinitialize the transcriber with the currently selected model.
    /// - Throws: `DictationError.cannotChangeModelWhileBusy` if not idle.
    func reloadSelectedModel() async throws {
        guard stateManager.isIdle else {
            throw DictationError.cannotChangeModelWhileBusy
        }

        let selectedModel = modelManager.selectedModel
        try await transcriber.initialize(model: selectedModel)
        logInfo("Transcriber model reloaded: \(selectedModel.rawValue)")
    }

    /// Start audio recording.
    /// - Parameter fromWakeWord: If `true`, recording auto-stops after detecting silence.
    func startRecording(fromWakeWord: Bool = false) async {
        logInfo("startRecording called (fromWakeWord: \(fromWakeWord), currentState: \(stateManager.state))")

        guard stateManager.isIdle else {
            logWarning("Cannot start recording: not in idle state (state: \(stateManager.state))")
            return
        }

        // Track if this was triggered by wake word for auto-stop
        isWakeWordTriggered = fromWakeWord

        // Start the recorder BEFORE claiming the recording state. If it throws,
        // no media has been paused yet, so fail straight to an error state.
        do {
            try activeRecorder.startRecording()
        } catch {
            logError("Failed to start recording: \(error)")
            mediaPlaybackCoordinator.resumeAfterRecording()
            stateManager.setError("Failed to start recording")
            waveformBridge.sendState(.error(message: "Failed to start"))
            return
        }

        // The recorder is live; claim the recording state synchronously (no
        // await in between) so a release callback observing `isRecording` and
        // the live mic are always consistent.
        stateManager.setRecording()
        recordingStartTime = Date()
        audioFeedback.playStart()
        logInfo(
            "Using \(useAudioKit ? "AudioKit" : "AVAudioEngine") recorder\(fromWakeWord ? " (wake word triggered, auto-stop enabled)" : "")"
        )

        // Pausing media can suspend the MainActor for hundreds of ms. A stop or
        // cancel may run during that window; re-check afterwards and, if we are
        // no longer the active recording, undo the media pause and bail so we
        // never leave the mic live with a stale FSM.
        if AppPreferences.shared.pauseMediaDuringRecording {
            await mediaPlaybackCoordinator.pauseForRecording()
            guard stateManager.isRecording else {
                logWarning("Recording superseded during media pause; resuming media")
                mediaPlaybackCoordinator.resumeAfterRecording()
                return
            }
        }

        waveformBridge.sendState(.recording)

        // Start audio level updates for the floating waveform
        startAudioLevelUpdates()

        // Start escape key monitor to cancel recording
        startEscapeMonitor()
    }

    /// Cancel recording without transcribing
    private func cancelRecording() {
        guard stateManager.isRecording else { return }

        logInfo("Recording cancelled by user")
        stopEscapeMonitor()
        stopAudioLevelUpdates()

        activeRecorder.cancelRecording()
        mediaPlaybackCoordinator.resumeAfterRecording()

        stateManager.setIdle()
        waveformBridge.sendState(.idle)
    }

    private func startEscapeMonitor() {
        // Use global monitor since we're a menu bar app without a key window
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == AppConstants.escapeKeyCode {
                logInfo("Escape pressed - cancelling recording")
                Task { @MainActor [weak self] in
                    self?.cancelRecording()
                }
            }
        }
        logDebug("Escape monitor started")
    }

    func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
            logDebug("Escape monitor stopped")
        }
    }

    private func startAudioLevelUpdates() {
        audioLevelPublisher.start(isWakeWordTriggered: isWakeWordTriggered)
    }

    func stopAudioLevelUpdates() {
        audioLevelPublisher.stop()
    }

    /// Stop recording, transcribe the captured audio, and insert the result at the cursor.
    func stopRecordingAndTranscribe() async {
        _ = await stopRecordingAndTranscribe(mode: .insertAtCursor)
    }

    /// Stop recording and return the transcription text for external controllers.
    /// - Returns: Formatted transcription text or a control error.
    func stopRecordingForExternalControl() async -> Result<String, ControlledTranscriptionError> {
        await stopRecordingAndTranscribe(mode: .returnTextOnly)
    }

    /// Cancel recording from an external control command.
    func cancelRecordingForExternalControl() {
        cancelRecording()
    }
}

extension DictationController: ModelReloading {}

extension DictationController: DictationControlHandling {
    var controlRecordingState: RecordingState {
        recordingState
    }

    var isControlIdle: Bool {
        isIdle
    }

    var isControlRecording: Bool {
        isRecording
    }

    func startControlRecording() async {
        await startRecording()
    }

    func stopControlRecording() async -> Result<String, ControlledTranscriptionError> {
        await stopRecordingForExternalControl()
    }

    func cancelControlRecording() {
        cancelRecordingForExternalControl()
    }
}

// MARK: - Errors

enum DictationError: Error, Equatable, LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case eventTapFailed
    case notInitialized
    case cannotChangeModelWhileBusy

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission denied. Please grant access in System Settings → Privacy & Security → Microphone."
        case .accessibilityPermissionDenied:
            "Accessibility permission denied. Please grant access in System Settings → Privacy & Security → Accessibility."
        case .eventTapFailed:
            "Failed to create event tap for Globe key. Please check Accessibility permissions."
        case .notInitialized:
            "Dictation controller not initialized"
        case .cannotChangeModelWhileBusy:
            "Stop recording/transcribing before changing transcription model."
        }
    }
}

/// Error type for external-control stop/cancel/start workflows.
enum ControlledTranscriptionError: Error, LocalizedError {
    case notRecording
    case noAudioCaptured
    case audioTooShort
    case emptyTranscription
    case voiceVerificationFailed
    case voiceVerificationError(String)
    case textInsertionFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRecording:
            "Not currently recording"
        case .noAudioCaptured:
            "No audio captured"
        case .audioTooShort:
            "Audio too short for transcription"
        case .emptyTranscription:
            "No transcription produced"
        case .voiceVerificationFailed:
            "Voice verification failed"
        case let .voiceVerificationError(message):
            "Voice verification error: \(message)"
        case let .textInsertionFailed(message):
            "Text insertion failed: \(message)"
        case let .transcriptionFailed(message):
            "Transcription failed: \(message)"
        }
    }
}
