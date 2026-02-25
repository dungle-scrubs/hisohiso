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
    /// `listeningFlag` is read from the audio thread without locking (atomic bool).
    @Published private(set) var isListening = false {
        didSet { listeningFlag = isListening }
    }

    private nonisolated(unsafe) var listeningFlag = false

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

    /// Audio buffer and VAD state — accessed from the audio thread, protected by `bufferLock`.
    private nonisolated(unsafe) var _audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// VAD state — protected by `bufferLock`.
    private nonisolated(unsafe) var _isSpeaking = false
    private nonisolated(unsafe) var _silenceFrames = 0
    private let silenceThreshold = AppConstants.wakeWordSilenceFrames
    private let speechThreshold: Float = AppConstants.wakeWordSpeechThreshold

    /// Whisper tiny for wake phrase detection
    /// Marked `nonisolated(unsafe)` because `WhisperKit.transcribe` is nonisolated but
    /// internally thread-safe. All writes happen on MainActor (init, deinit).
    private nonisolated(unsafe) var whisperKit: WhisperKit?
    private var isProcessing = false

    /// Pre-buffer to capture audio before speech is detected — protected by `bufferLock`.
    private nonisolated(unsafe) var _preBuffer: [[Float]] = []
    private let preBufferFrames = AppConstants.wakeWordPreBufferFrames

    /// Maximum buffer size (~3 seconds at 16kHz)
    private let maxBufferSamples = AppConstants.maxWakeWordBufferSamples

    /// Frame counter for debug logging — protected by `bufferLock`.
    private nonisolated(unsafe) var _frameCounter = 0

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
        bufferLock.lock()
        _audioBuffer.removeAll()
        _preBuffer.removeAll()
        bufferLock.unlock()
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

        // Read listening state without locking — atomic bool read.
        // Worst case: we process one extra buffer after stopListening.
        guard listeningFlag else { return }

        // Resample to 16kHz if needed
        let resampled: [Float] = if abs(sampleRate - AppConstants.targetSampleRate) > 1 {
            AudioDSP.resample(samples, from: sampleRate, to: AppConstants.targetSampleRate)
        } else {
            samples
        }

        // Calculate RMS for VAD
        var rms: Float = 0
        vDSP_rmsqv(resampled, 1, &rms, vDSP_Length(resampled.count))

        let isSpeechFrame = rms > speechThreshold

        bufferLock.lock()

        // Debug logging every ~8.5 seconds
        _frameCounter += 1
        if _frameCounter % 100 == 1 {
            let fc = _frameCounter
            bufferLock.unlock()
            logDebug("WakeWordManager: Audio frame \(fc), RMS: \(String(format: "%.4f", rms))")
            bufferLock.lock()
        }

        // Always keep a pre-buffer of recent audio
        _preBuffer.append(resampled)
        if _preBuffer.count > preBufferFrames {
            _preBuffer.removeFirst()
        }

        if isSpeechFrame {
            if !_isSpeaking {
                _isSpeaking = true
                _silenceFrames = 0
                logDebug("WakeWordManager: Speech started (RMS: \(String(format: "%.4f", rms)))")

                for frame in _preBuffer {
                    _audioBuffer.append(contentsOf: frame)
                }
                _preBuffer.removeAll()
            }

            _audioBuffer.append(contentsOf: resampled)

            if _audioBuffer.count > maxBufferSamples {
                _audioBuffer.removeFirst(_audioBuffer.count - maxBufferSamples)
            }

            _silenceFrames = 0
        } else if _isSpeaking {
            _audioBuffer.append(contentsOf: resampled)
            _silenceFrames += 1

            if _silenceFrames >= silenceThreshold {
                _isSpeaking = false
                let samplesForProcessing = _audioBuffer
                _audioBuffer.removeAll()
                bufferLock.unlock()

                // Only dispatch to MainActor for the actual wake-phrase check
                Task { @MainActor [weak self] in
                    await self?.checkForWakePhrase(samples: samplesForProcessing)
                }
                return
            }
        }

        bufferLock.unlock()
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

        do {
            let result = try await whisperKit.transcribe(audioArray: samples)
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
