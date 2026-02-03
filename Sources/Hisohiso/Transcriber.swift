import Foundation
import WhisperKit

/// Transcription model options
enum TranscriptionModel: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base.en"
    case small = "openai_whisper-small.en"
    case largeV3Turbo = "openai_whisper-large-v3-turbo"
    case distilLargeV3 = "distil-whisper_distil-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~66 MB)"
        case .base: return "Base English (~105 MB)"
        case .small: return "Small English (~330 MB)"
        case .largeV3Turbo: return "Large V3 Turbo (~954 MB)"
        case .distilLargeV3: return "Distil Large V3 (~800 MB)"
        }
    }

    /// Default model for best balance of speed and accuracy
    /// Using tiny for faster transcription during development
    static let defaultModel: TranscriptionModel = .tiny
}

/// Error types for transcription
enum TranscriberError: Error, LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case transcriptionFailed(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcriber not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .timeout:
            return "Transcription timed out"
        }
    }
}

/// WhisperKit-based transcription service
actor Transcriber {
    private var whisperKit: WhisperKit?
    private let timeoutSeconds: TimeInterval = 30

    /// Initialize the transcriber with a specific model
    /// - Parameter model: The model to use for transcription
    func initialize(model: TranscriptionModel = .defaultModel) async throws {
        logInfo("Initializing transcriber with model: \(model.rawValue)")

        do {
            whisperKit = try await WhisperKit(
                model: model.rawValue,
                verbose: false,
                logLevel: .none
            )
            logInfo("Transcriber initialized, warming up...")
            
            // Warmup with silent audio to prime the Neural Engine
            if let kit = whisperKit {
                let silentAudio = [Float](repeating: 0, count: 16000) // 1 second of silence
                _ = try? await kit.transcribe(audioArray: silentAudio)
            }
            logInfo("Transcriber warmed up and ready")
        } catch {
            logError("Failed to initialize transcriber: \(error)")
            throw TranscriberError.modelNotFound(model.rawValue)
        }
    }

    /// Transcribe audio samples to text
    /// - Parameter audioSamples: Audio samples at 16kHz mono
    /// - Returns: Transcribed text
    func transcribe(_ audioSamples: [Float]) async throws -> String {
        guard let whisperKit else {
            throw TranscriberError.notInitialized
        }

        logInfo("Starting transcription of \(audioSamples.count) samples")

        // Capture whisperKit locally to avoid self capture in task group
        let kit = whisperKit
        let timeout = timeoutSeconds

        // Use withThrowingTaskGroup to implement timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Add transcription task
            group.addTask {
                let results = try await kit.transcribe(audioArray: audioSamples)
                return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranscriberError.timeout
            }

            // Return first successful result, cancel the other
            guard let result = try await group.next() else {
                throw TranscriberError.transcriptionFailed(NSError(domain: "Transcriber", code: -1))
            }

            group.cancelAll()
            logInfo("Transcription complete: \(result.prefix(50))...")
            return result
        }
    }

    /// Check if transcriber is ready
    var isReady: Bool {
        whisperKit != nil
    }
}
