import Foundation

/// Coordinates the dictation flow: Globe key → recording → transcription → text insertion
@MainActor
final class DictationController: ObservableObject {
    private let globeMonitor = GlobeKeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let textInserter = TextInserter()
    private let textFormatter = TextFormatter()
    private let audioFeedback = AudioFeedback()
    private let modelManager: ModelManager

    @Published private(set) var stateManager = RecordingStateManager()

    private var isInitialized = false

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
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

        isInitialized = true
        logInfo("DictationController initialized")
    }

    /// Stop the controller
    func shutdown() {
        globeMonitor.stop()
        if stateManager.isRecording {
            audioRecorder.cancelRecording()
        }
        stateManager.setIdle()
        logInfo("DictationController shutdown")
    }

    private func setupCallbacks() {
        // Tap: toggle recording on/off
        globeMonitor.onGlobeTap = { [weak self] in
            guard let self else { return }
            Task { await self.toggleRecording() }
        }
        
        // Hold: start recording
        globeMonitor.onGlobeHoldStart = { [weak self] in
            guard let self else { return }
            Task { await self.startRecording() }
        }
        
        // Release after hold: stop recording
        globeMonitor.onGlobeHoldEnd = { [weak self] in
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
        if stateManager.isIdle {
            await startRecording()
        } else if stateManager.isRecording {
            await stopRecordingAndTranscribe()
        }
        // Ignore if transcribing or in error state
    }
    
    private func startRecording() async {
        guard stateManager.isIdle else {
            logDebug("Cannot start recording: not in idle state")
            return
        }

        do {
            audioFeedback.playStart()
            try audioRecorder.startRecording()
            stateManager.setRecording()
        } catch {
            logError("Failed to start recording: \(error)")
            stateManager.setError("Failed to start recording")
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard stateManager.isRecording else {
            logWarning("Cannot stop recording: not recording")
            return
        }

        audioFeedback.playStop()
        let audioSamples = audioRecorder.stopRecording()

        guard !audioSamples.isEmpty else {
            logWarning("No audio captured")
            stateManager.setIdle()
            return
        }

        // Minimum audio length check (~0.5 seconds)
        let minSamples = 8000 // 0.5s at 16kHz
        guard audioSamples.count >= minSamples else {
            logInfo("Audio too short (\(audioSamples.count) samples), ignoring")
            stateManager.setIdle()
            return
        }

        stateManager.setTranscribing()

        do {
            let rawText = try await transcriber.transcribe(audioSamples)

            guard !rawText.isEmpty else {
                logInfo("Empty transcription result")
                stateManager.setIdle()
                return
            }

            let formattedText = textFormatter.format(rawText)
            logInfo("Formatted: '\(rawText)' → '\(formattedText)'")
            
            try textInserter.insert(formattedText)
            stateManager.setIdle()
        } catch let error as TranscriberError {
            logError("Transcription error: \(error)")
            switch error {
            case .timeout:
                stateManager.setError("Transcription timed out")
            default:
                stateManager.setError(error.localizedDescription)
            }
        } catch {
            logError("Error during transcription: \(error)")
            stateManager.setError(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum DictationError: Error, LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case eventTapFailed
    case notInitialized

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
        }
    }
}
