import Foundation

/// Transcription seam consumed by `DictationController`.
///
/// Captures exactly the `Transcriber` surface the controller depends on so
/// tests can inject a fake backend without loading a real speech model.
/// `Transcriber` conforms retroactively; production wiring is unchanged.
protocol TranscribingService: Sendable {
    /// Initialize the backend with a specific model.
    /// - Parameter model: The model to load for transcription.
    func initialize(model: TranscriptionModel) async throws

    /// Transcribe 16kHz mono audio samples to text.
    /// - Parameter audioSamples: Audio samples at 16kHz mono.
    /// - Returns: Transcribed text.
    func transcribe(_ audioSamples: [Float]) async throws -> String
}

extension Transcriber: TranscribingService {}
