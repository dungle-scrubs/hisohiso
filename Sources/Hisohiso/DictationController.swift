import Accelerate
import Cocoa
import Foundation

/// Coordinates the dictation flow: Globe key → recording → transcription → text insertion
@MainActor
final class DictationController: ObservableObject {
    private let globeMonitor = GlobeKeyMonitor()
    let audioRecorder = AudioRecorder()
    private let audioKitRecorder = AudioKitRecorder()
    private let transcriber = Transcriber()

    /// Whether to use AudioKit for recording (with noise handling)
    var useAudioKit: Bool {
        get { UserDefaults.standard.bool(forKey: "useAudioKit") }
        set { UserDefaults.standard.set(newValue, forKey: "useAudioKit") }
    }
    private let textInserter = TextInserter()
    private let audioFeedback = AudioFeedback()
    private let modelManager: ModelManager
    private let hotkeyManager: HotkeyManager?
    private let historyStore = HistoryStore.shared
    private let sinewBridge = SinewBridge.shared

    @Published private(set) var stateManager = RecordingStateManager()

    /// Track recording start time for duration calculation
    private var recordingStartTime: Date?

    /// Timer for sending audio levels to Sinew/floating UI.
    private var audioLevelTimer: Timer?

    /// Callback for audio level updates (for UI waveform)
    var onAudioLevels: (([UInt8]) -> Void)?

    /// Monitor for escape key to cancel recording
    private var escapeMonitor: Any?

    /// Whether current recording was triggered by wake word (auto-stop on silence)
    private var isWakeWordTriggered = false
    
    /// Silence detection for wake word auto-stop
    private var silenceFrameCount = 0
    private let silenceThresholdForStop = 25 // ~1.25s of silence to auto-stop (after grace period)
    private let silenceRMSThreshold: Float = 0.01
    
    /// Grace period before silence detection starts (3 seconds = 60 frames at 50ms)
    private var gracePeriodFrames = 0
    private let gracePeriodThreshold = 60 // 3 seconds at 50ms per frame

    private var isInitialized = false

    init(modelManager: ModelManager, hotkeyManager: HotkeyManager? = nil) {
        self.modelManager = modelManager
        self.hotkeyManager = hotkeyManager
        setupCallbacks()
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
            if useAudioKit {
                audioKitRecorder.cancelRecording()
            } else {
                audioRecorder.cancelRecording()
            }
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
            if self.stateManager.isRecording {
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
            guard self.stateManager.isRecording else { return }
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
    func reloadSelectedModel() async throws {
        guard stateManager.isIdle else {
            throw DictationError.cannotChangeModelWhileBusy
        }

        let selectedModel = modelManager.selectedModel
        try await transcriber.initialize(model: selectedModel)
        logInfo("Transcriber model reloaded: \(selectedModel.rawValue)")
    }

    /// Start recording (can be called externally by wake word)
    /// - Parameter fromWakeWord: If true, recording will auto-stop after silence
    func startRecording(fromWakeWord: Bool = false) async {
        logInfo("startRecording called (fromWakeWord: \(fromWakeWord), currentState: \(stateManager.state))")
        
        guard stateManager.isIdle else {
            logWarning("Cannot start recording: not in idle state (state: \(stateManager.state))")
            return
        }

        // Track if this was triggered by wake word for auto-stop
        isWakeWordTriggered = fromWakeWord
        silenceFrameCount = 0
        gracePeriodFrames = 0

        // Set state FIRST so release callback knows we're recording
        stateManager.setRecording()
        audioFeedback.playStart()
        recordingStartTime = Date()

        do {
            if useAudioKit {
                try audioKitRecorder.startRecording()
                logInfo("Using AudioKit recorder")
            } else {
                try audioRecorder.startRecording()
                logInfo("Using AVAudioEngine recorder\(fromWakeWord ? " (wake word triggered, auto-stop enabled)" : "")")
            }

            // Notify Sinew
            sinewBridge.sendState(.recording)

            // Start audio level updates for Sinew/floating waveform
            startAudioLevelUpdates()

            // Start escape key monitor to cancel recording
            startEscapeMonitor()
        } catch {
            logError("Failed to start recording: \(error)")
            stateManager.setError("Failed to start recording")
            sinewBridge.sendState(.error(message: "Failed to start"))
        }
    }

    /// Cancel recording without transcribing
    private func cancelRecording() {
        guard stateManager.isRecording else { return }

        logInfo("Recording cancelled by user")
        stopEscapeMonitor()
        stopAudioLevelUpdates()

        if useAudioKit {
            audioKitRecorder.cancelRecording()
        } else {
            audioRecorder.cancelRecording()
        }

        stateManager.setIdle()
        sinewBridge.sendState(.idle)
    }

    private func startEscapeMonitor() {
        // Use global monitor since we're a menu bar app without a key window
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                logInfo("Escape pressed - cancelling recording")
                Task { @MainActor [weak self] in
                    self?.cancelRecording()
                }
            }
        }
        logDebug("Escape monitor started")
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
            logDebug("Escape monitor stopped")
        }
    }

    private func startAudioLevelUpdates() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAudioLevelTick()
            }
        }
    }

    @MainActor
    private func handleAudioLevelTick() {
        // Get recent audio samples from recorder
        let samples: [Float]
        if useAudioKit {
            samples = audioKitRecorder.getRecentSamples(count: 1600)
        } else {
            samples = audioRecorder.getRecentSamples(count: 1600)
        }

        // Calculate levels and send to Sinew and UI
        let levels = SinewBridge.calculateAudioLevels(from: samples)
        sinewBridge.sendAudioLevels(levels)
        onAudioLevels?(levels)

        // Auto-stop on silence for wake word triggered recordings
        if isWakeWordTriggered {
            checkSilenceForAutoStop(samples: samples)
        }
    }
    
    /// Check for silence and auto-stop if wake word triggered
    private func checkSilenceForAutoStop(samples: [Float]) {
        guard !samples.isEmpty else { return }
        
        // Increment grace period counter
        gracePeriodFrames += 1
        
        // Don't check for silence during grace period (first 3 seconds)
        guard gracePeriodFrames >= gracePeriodThreshold else {
            return
        }
        
        // Calculate RMS
        var rms: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            vDSP_rmsqv(buffer.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        }
        
        if rms < silenceRMSThreshold {
            silenceFrameCount += 1
            if silenceFrameCount >= silenceThresholdForStop {
                logInfo("Wake word recording: auto-stopping after \(silenceFrameCount) frames of silence (grace period: \(gracePeriodFrames) frames)")
                Task { @MainActor in
                    await self.stopRecordingAndTranscribe()
                }
            }
        } else {
            // Reset silence counter when speech detected
            silenceFrameCount = 0
        }
    }

    private func stopAudioLevelUpdates() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    /// Stop recording and transcribe (can be called externally by wake word)
    func stopRecordingAndTranscribe() async {
        guard stateManager.isRecording else {
            logWarning("Cannot stop recording: not recording")
            return
        }

        audioFeedback.playStop()
        stopAudioLevelUpdates()
        stopEscapeMonitor()

        let audioSamples: [Float]
        if useAudioKit {
            audioSamples = audioKitRecorder.stopRecording()
        } else {
            audioSamples = audioRecorder.stopRecording()
        }

        // Notify Sinew of transcribing state
        sinewBridge.sendState(.transcribing)

        // Calculate recording duration
        let duration: TimeInterval
        if let startTime = recordingStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = Double(audioSamples.count) / 16000.0 // Estimate from samples
        }
        recordingStartTime = nil

        guard !audioSamples.isEmpty else {
            logWarning("No audio captured")
            stateManager.setIdle()
            sinewBridge.sendState(.idle)
            return
        }

        // Minimum audio length check - Parakeet needs at least 1 second (16000 samples)
        let minSamples = 16000 // 1s at 16kHz
        guard audioSamples.count >= minSamples else {
            logInfo("Audio too short (\(audioSamples.count) samples, need \(minSamples)), ignoring")
            // Just go back to idle silently - no error, just not enough audio
            stateManager.setIdle()
            sinewBridge.sendState(.idle)
            return
        }

        stateManager.setTranscribing()

        // Debug: Save audio to file for analysis
        #if DEBUG
        saveDebugAudio(audioSamples)
        #endif

        // Voice verification (if enabled)
        if VoiceVerifier.shared.isEnabled, VoiceVerifier.shared.isEnrolled {
            do {
                let verificationResult = try await VoiceVerifier.shared.verify(audioSamples: audioSamples)
                if !verificationResult.isMatch {
                    logInfo("Voice verification failed (similarity: \(String(format: "%.2f", verificationResult.similarity)))")
                    stateManager.setIdle()
                    sinewBridge.sendState(.idle)
                    return
                }
                logDebug("Voice verified (similarity: \(String(format: "%.2f", verificationResult.similarity)))")
            } catch {
                // If verification fails, log but continue with transcription
                logWarning("Voice verification error: \(error.localizedDescription)")
            }
        }

        do {
            let rawText = try await transcriber.transcribe(audioSamples)

            guard !rawText.isEmpty else {
                logInfo("Empty transcription result")
                stateManager.setIdle()
                sinewBridge.sendState(.idle)
                return
            }

            let formattedText = TextFormatter().format(rawText)
            logInfo("Formatted: '\(rawText)' → '\(formattedText)'")

            // Save to history
            let modelName = modelManager.selectedModel.displayName
            historyStore.save(text: formattedText, duration: duration, modelName: modelName)

            try textInserter.insert(formattedText)
            stateManager.setIdle()
            sinewBridge.sendState(.idle)
        } catch let error as TranscriberError {
            logError("Transcription error: \(error)")
            switch error {
            case .timeout:
                sinewBridge.sendState(.error(message: "Timed out"))
                stateManager.setError("Transcription timed out")
            case .invalidAudioData:
                // Audio too short or invalid - just go back to idle silently
                logInfo("Audio too short for transcription")
                stateManager.setIdle()
                sinewBridge.sendState(.idle)
            default:
                sinewBridge.sendState(.error(message: error.localizedDescription))
                stateManager.setError(error.localizedDescription)
            }
        } catch {
            logError("Error during transcription: \(error)")
            sinewBridge.sendState(.error(message: error.localizedDescription))
            stateManager.setError(error.localizedDescription)
        }
    }

    #if DEBUG
    /// Maximum number of debug audio files to keep.
    private static let maxDebugAudioFiles = 10

    /// Save audio samples to file for debugging, pruning old files.
    private func saveDebugAudio(_ samples: [Float]) {
        let debugDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hisohiso-debug")
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = debugDir.appendingPathComponent("\(timestamp).raw")

        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        do {
            try data.write(to: path)
            logInfo("Debug audio saved to \(path.path) (\(samples.count) samples)")
            pruneDebugAudio(in: debugDir)
        } catch {
            logError("Failed to save debug audio: \(error)")
        }
    }

    /// Keep only the most recent debug audio files.
    private func pruneDebugAudio(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .sorted(by: { ($0.lastPathComponent) > ($1.lastPathComponent) })
        else { return }

        for file in files.dropFirst(Self.maxDebugAudioFiles) {
            try? fm.removeItem(at: file)
        }
    }
    #endif
}

// MARK: - Errors

enum DictationError: Error, LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case eventTapFailed
    case notInitialized
    case cannotChangeModelWhileBusy

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please grant access in System Settings → Privacy & Security → Microphone."
        case .accessibilityPermissionDenied:
            return "Accessibility permission denied. Please grant access in System Settings → Privacy & Security → Accessibility."
        case .eventTapFailed:
            return "Failed to create event tap for Globe key. Please check Accessibility permissions."
        case .notInitialized:
            return "Dictation controller not initialized"
        case .cannotChangeModelWhileBusy:
            return "Stop recording/transcribing before changing transcription model."
        }
    }
}
