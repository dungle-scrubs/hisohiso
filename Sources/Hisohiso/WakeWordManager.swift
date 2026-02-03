import AVFoundation
import Accelerate
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
            UserDefaults.standard.set(isEnabled, forKey: "wakeWordEnabled")
        }
    }

    /// Whether currently listening for wake word
    @Published private(set) var isListening = false

    /// The configured wake phrase (e.g., "hey kevin", "computer")
    var wakePhrase: String {
        get { UserDefaults.standard.string(forKey: "wakePhrase") ?? "hey hisohiso" }
        set { UserDefaults.standard.set(newValue.lowercased().trimmingCharacters(in: .whitespaces), forKey: "wakePhrase") }
    }

    /// Callback when wake word is detected
    var onWakeWordDetected: (() -> Void)?

    // MARK: - Private Properties

    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// VAD state
    private var isSpeaking = false
    private var silenceFrames = 0
    private let silenceThreshold = 10 // ~850ms of silence
    private let speechThreshold: Float = 0.015 // RMS threshold

    /// Whisper tiny for wake phrase detection
    private var whisperKit: WhisperKit?
    private var isProcessing = false

    /// Pre-buffer to capture audio before speech is detected
    private var preBuffer: [[Float]] = []
    private let preBufferFrames = 5 // Keep ~425ms of audio before speech detected

    /// Maximum buffer size (~3 seconds at 16kHz)
    private let maxBufferSamples = 48000

    /// Frame counter for debug logging
    private var frameCounter = 0

    // MARK: - Initialization

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "wakeWordEnabled")
        self.isEnabled = enabled
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
        audioBuffer.removeAll()
        preBuffer.removeAll()
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

    /// Feed audio samples from AudioRecorder's monitoring tap
    /// - Parameters:
    ///   - samples: Audio samples (should be 16kHz mono)
    ///   - sampleRate: Sample rate of the audio
    func processAudioSamples(_ samples: [Float], sampleRate: Double) {
        guard isListening else { return }
        guard !samples.isEmpty else { return }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if sampleRate != 16000 {
            resampled = resampleTo16kHz(samples, fromRate: sampleRate)
        } else {
            resampled = samples
        }

        // Calculate RMS for VAD
        var rms: Float = 0
        vDSP_rmsqv(resampled, 1, &rms, vDSP_Length(resampled.count))

        // Debug logging every ~8.5 seconds
        frameCounter += 1
        if frameCounter % 100 == 1 {
            logDebug("WakeWordManager: Audio frame \(frameCounter), RMS: \(String(format: "%.4f", rms))")
        }

        let isSpeechFrame = rms > speechThreshold

        bufferLock.lock()
        defer { bufferLock.unlock() }

        // Always keep a pre-buffer of recent audio
        preBuffer.append(resampled)
        if preBuffer.count > preBufferFrames {
            preBuffer.removeFirst()
        }

        if isSpeechFrame {
            // Speech detected
            if !isSpeaking {
                isSpeaking = true
                silenceFrames = 0
                logDebug("WakeWordManager: Speech started (RMS: \(String(format: "%.4f", rms)))")

                // Add pre-buffer to capture the start of speech
                for frame in preBuffer {
                    audioBuffer.append(contentsOf: frame)
                }
                preBuffer.removeAll()
            }

            // Add current frame to buffer
            audioBuffer.append(contentsOf: resampled)

            // Limit buffer size
            if audioBuffer.count > maxBufferSamples {
                audioBuffer.removeFirst(audioBuffer.count - maxBufferSamples)
            }

            silenceFrames = 0
        } else if isSpeaking {
            // Silence after speech - still add to buffer to capture trailing audio
            audioBuffer.append(contentsOf: resampled)
            silenceFrames += 1

            if silenceFrames >= silenceThreshold {
                // End of speech - check for wake phrase
                isSpeaking = false
                let samplesForProcessing = audioBuffer
                audioBuffer.removeAll()

                // Process in background
                Task { [weak self] in
                    await self?.checkForWakePhrase(samples: samplesForProcessing)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func resampleTo16kHz(_ samples: [Float], fromRate: Double) -> [Float] {
        guard fromRate != 16000 else { return samples }

        let ratio = 16000.0 / fromRate
        let outputLength = Int(Double(samples.count) * ratio)
        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)
        var control = (0 ..< outputLength).map { Float($0) / Float(ratio) }
        vDSP_vlint(samples, &control, 1, &output, 1, vDSP_Length(outputLength), vDSP_Length(samples.count))

        return output
    }

    private func checkForWakePhrase(samples: [Float]) async {
        guard !isProcessing else {
            logDebug("WakeWordManager: Already processing, skipping")
            return
        }

        logDebug("WakeWordManager: Checking \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")

        guard samples.count >= 8000 else {
            logDebug("WakeWordManager: Too few samples (\(samples.count) < 8000)")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        guard let whisperKit = whisperKit else {
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
