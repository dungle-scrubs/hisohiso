import Foundation
import WhisperKit

/// Callback for streaming transcription updates
typealias TranscriptionCallback = @MainActor (String, Bool) -> Void

/// Streaming transcription service that provides real-time results
actor StreamingTranscriber {
    private var whisperKit: WhisperKit?
    private var audioBuffer: [Float] = []
    private var lastTranscription: String = ""
    private var isTranscribing = false
    
    /// Minimum audio samples before attempting transcription (0.5 seconds at 16kHz)
    private let minSamplesForTranscription = 8000
    
    /// Chunk size for incremental transcription (1 second at 16kHz)
    private let chunkSize = 16000

    /// Initialize with a model
    func initialize(model: TranscriptionModel = .defaultModel) async throws {
        logInfo("Initializing streaming transcriber with model: \(model.rawValue)")

        do {
            whisperKit = try await WhisperKit(
                model: model.rawValue,
                verbose: false,
                logLevel: .none
            )
            logInfo("Streaming transcriber initialized")
        } catch {
            logError("Failed to initialize streaming transcriber: \(error)")
            throw TranscriberError.modelNotFound(model.rawValue)
        }
    }

    /// Add audio samples to the buffer and trigger transcription if ready
    /// - Parameters:
    ///   - samples: New audio samples at 16kHz
    ///   - callback: Called with (text, isFinal) updates
    func addSamples(_ samples: [Float], callback: TranscriptionCallback) async {
        audioBuffer.append(contentsOf: samples)
        
        // Only transcribe if we have enough audio and not already transcribing
        guard audioBuffer.count >= minSamplesForTranscription, !isTranscribing else {
            return
        }
        
        await transcribeBuffer(callback: callback, isFinal: false)
    }

    /// Finalize transcription with all remaining audio
    /// - Parameter callback: Called with final result
    func finalize(callback: TranscriptionCallback) async {
        guard !audioBuffer.isEmpty else {
            await callback("", true)
            return
        }
        
        await transcribeBuffer(callback: callback, isFinal: true)
        reset()
    }

    /// Reset the transcriber state
    func reset() {
        audioBuffer = []
        lastTranscription = ""
        isTranscribing = false
    }

    /// Check if ready
    var isReady: Bool {
        whisperKit != nil
    }

    // MARK: - Private

    private func transcribeBuffer(callback: TranscriptionCallback, isFinal: Bool) async {
        guard let whisperKit, !audioBuffer.isEmpty else { return }
        
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let results = try await whisperKit.transcribe(audioArray: audioBuffer)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            
            if text != lastTranscription {
                lastTranscription = text
                await callback(text, isFinal)
                logDebug("Streaming result (\(isFinal ? "final" : "partial")): \(text.prefix(50))...")
            }
        } catch {
            logError("Streaming transcription error: \(error)")
        }
    }
}
