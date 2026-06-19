import Accelerate
import AVFoundation
import Foundation
import WhisperKit

/// Manages wake word detection using VAD + Whisper tiny
/// Receives audio samples from AudioRecorder's continuous monitoring tap
@MainActor
final class WakeWordManager: ObservableObject {
    // MARK: - Published Properties

    /// Whether wake word detection is enabled
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, for: .wakeWordEnabled)
        }
    }

    /// Whether currently listening for wake word.
    @Published private(set) var isListening = false {
        didSet { wakeState.setListening(isListening) }
    }

    private nonisolated let wakeState = WakeWordStateStore()

    /// The configured wake phrase (e.g., "hey kevin", "computer").
    /// Empty or whitespace-only values are rejected to prevent false activations.
    var wakePhrase: String {
        get { UserDefaults.standard.string(for: .wakePhrase) ?? AppConstants.defaultWakePhrase }
        set {
            let trimmed = newValue.lowercased().trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                logWarning("WakeWordManager: Rejecting empty wake phrase")
                return
            }
            UserDefaults.standard.set(trimmed, for: .wakePhrase)
        }
    }

    /// Callback when wake word is detected
    var onWakeWordDetected: (() -> Void)?

    // MARK: - Private Properties

    /// Whisper tiny for wake phrase detection.
    /// Narrow actor escape: WhisperKit's transcribe method is nonisolated and
    /// model ownership is initialized on the main actor, then read for inference.
    private nonisolated(unsafe) var whisperKit: WhisperKit?
    private var isProcessing = false

    // MARK: - Initialization

    init() {
        let enabled = UserDefaults.standard.bool(for: .wakeWordEnabled)
        isEnabled = enabled
    }

    // MARK: - Public Methods

    /// Initialize Whisper tiny for wake phrase detection
    func initialize() async throws {
        guard whisperKit == nil else { return }

        logInfo("WakeWordManager: Initializing Whisper tiny for wake phrase detection...")

        // Use the smallest English model for fast wake phrase detection
        whisperKit = try await WhisperKit(
            model: "openai_whisper-tiny.en",
            verbose: false,
            logLevel: .none
        )

        logInfo("WakeWordManager: Whisper tiny ready")
    }

    /// Start listening mode (call after Whisper is initialized)
    func startListening() {
        guard isEnabled else { return }
        isListening = true
        logInfo("WakeWordManager: Started listening for '\(wakePhrase)'")
    }

    /// Stop listening
    func stopListening() {
        isListening = false
        wakeState.resetBuffers()
        logInfo("WakeWordManager: Stopped listening")
    }

    /// Pause listening (e.g., during dictation)
    func pauseListening() {
        isListening = false
        logDebug("WakeWordManager: Paused")
    }

    /// Resume listening
    func resumeListening() {
        guard isEnabled else { return }
        isListening = true
        logDebug("WakeWordManager: Resumed")
    }

    /// Feed audio samples from AudioRecorder's monitoring tap.
    ///
    /// Called from the audio render thread. VAD processing happens inline
    /// to avoid ~85 MainActor dispatches/second. Only wake-phrase checking
    /// dispatches to MainActor.
    nonisolated func processAudioSamples(_ samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }

        guard wakeState.isListening() else { return }

        // Resample to 16kHz if needed
        let resampled: [Float] = if abs(sampleRate - AppConstants.targetSampleRate) > 1 {
            AudioDSP.resample(samples, from: sampleRate, to: AppConstants.targetSampleRate)
        } else {
            samples
        }

        // Calculate RMS for VAD
        var rms: Float = 0
        vDSP_rmsqv(resampled, 1, &rms, vDSP_Length(resampled.count))

        let isSpeechFrame = rms > AppConstants.wakeWordSpeechThreshold

        switch wakeState.ingest(
            samples: resampled,
            isSpeechFrame: isSpeechFrame,
            silenceThreshold: AppConstants.wakeWordSilenceFrames,
            preBufferFrames: AppConstants.wakeWordPreBufferFrames,
            maxBufferSamples: AppConstants.maxWakeWordBufferSamples
        ) {
        case .none:
            return
        case let .debugFrame(count):
            logDebug("WakeWordManager: Audio frame \(count), RMS: \(String(format: "%.4f", rms))")
        case let .process(samplesForProcessing):
            Task { @MainActor [weak self] in
                await self?.checkForWakePhrase(samples: samplesForProcessing)
            }
        }
    }

    // MARK: - Private Methods

    private func checkForWakePhrase(samples: [Float]) async {
        guard !isProcessing else {
            logDebug("WakeWordManager: Already processing, skipping")
            return
        }

        logDebug(
            "WakeWordManager: Checking \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)"
        )

        guard samples.count >= AppConstants.minWakeWordSamples else {
            logDebug("WakeWordManager: Too few samples (\(samples.count) < \(AppConstants.minWakeWordSamples))")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        guard let whisperKit else {
            logError("WakeWordManager: WhisperKit not initialized")
            return
        }
        let whisperKitBox = UncheckedSendableBox(value: whisperKit)

        do {
            let result = try await whisperKitBox.value.transcribe(audioArray: samples)
            var text = result.first?.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Filter out Whisper hallucinations (non-speech sounds in parentheses/brackets)
            if text.hasPrefix("(") || text.hasPrefix("[") || text.hasPrefix("♪") {
                logDebug("WakeWordManager: Ignoring non-speech: '\(text)'")
                return
            }

            // Remove any parenthetical content
            text = text.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            guard !text.isEmpty else { return }

            logInfo("WakeWordManager: Heard '\(text)' (looking for '\(wakePhrase)')")

            // Check if transcription contains wake phrase
            if containsWakePhrase(text) {
                logInfo("WakeWordManager: Wake phrase detected!")
                await MainActor.run {
                    self.onWakeWordDetected?()
                }
            }
        } catch {
            logError("WakeWordManager: Transcription failed: \(error)")
        }
    }

    private func containsWakePhrase(_ text: String) -> Bool {
        let normalizedText = text.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)

        let normalizedWake = wakePhrase.lowercased()

        // Check for exact match at start, or close variants
        return normalizedText.hasPrefix(normalizedWake) ||
            normalizedText.contains(normalizedWake)
    }
}
