import Foundation

/// Speaker-verification seam consumed by `DictationController`.
///
/// Captures exactly the `VoiceVerifier` surface the controller depends on so
/// tests can inject a fake verifier without a CoreML model or enrollment.
/// `VoiceVerifier` conforms retroactively; production wiring is unchanged.
protocol VoiceVerifying: Sendable {
    /// Whether speaker verification is enabled.
    var isEnabled: Bool { get }

    /// Whether a voice has been enrolled.
    var isEnrolled: Bool { get }

    /// Verify whether the given audio matches the enrolled voice.
    /// - Parameter audioSamples: Audio samples at 16kHz mono.
    /// - Returns: Verification result with match status and similarity score.
    func verify(audioSamples: [Float]) async throws -> VerificationResult
}

extension VoiceVerifier: VoiceVerifying {}
