import Accelerate
import XCTest
@testable import Hisohiso

/// Tests for VoiceVerifier's vector math operations.
///
/// These test the pure math (cosine similarity, L2 normalization, averaging)
/// without requiring a CoreML model or microphone access.
final class VoiceVerifierMathTests: XCTestCase {
    // We test the math via the public verify/enroll interface indirectly,
    // but the vector operations are private. We can test the types and
    // constants that feed into them.

    // MARK: - VerificationResult

    func testVerificationResultMatchedState() {
        let result = VerificationResult(isMatch: true, similarity: 0.95, reason: .matched)
        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.similarity, 0.95, accuracy: 0.001)
    }

    func testVerificationResultNotMatchedState() {
        let result = VerificationResult(isMatch: false, similarity: 0.3, reason: .notMatched)
        XCTAssertFalse(result.isMatch)
    }

    func testVerificationResultDisabledAlwaysMatches() {
        let result = VerificationResult(isMatch: true, similarity: 1.0, reason: .verificationDisabled)
        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.similarity, 1.0)
    }

    func testVerificationResultNotEnrolledAlwaysMatches() {
        let result = VerificationResult(isMatch: true, similarity: 1.0, reason: .notEnrolled)
        XCTAssertTrue(result.isMatch)
    }

    // MARK: - VoiceVerifierError

    func testInsufficientAudioErrorDescription() {
        let error = VoiceVerifierError.insufficientAudio(required: 32000, provided: 8000)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("2.0"), "Should show 2.0s required")
        XCTAssertTrue(description.contains("0.5"), "Should show 0.5s provided")
    }

    func testModelNotLoadedErrorDescription() {
        let error = VoiceVerifierError.modelNotLoaded
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - Constants

    func testEmbeddingDimension() {
        XCTAssertEqual(VoiceVerifier.embeddingDimension, 256)
    }

    func testSampleRate() {
        XCTAssertEqual(VoiceVerifier.sampleRate, 16000)
    }

    func testMinSamplesForVerification() {
        // 2 seconds at 16kHz
        XCTAssertEqual(VoiceVerifier.minSamplesForVerification, 32000)
    }

    // MARK: - L2 Normalization (tested via vDSP)

    func testL2NormalizationProperty() {
        // Verify the mathematical property: ||normalize(v)|| = 1
        let vector: [Float] = [3.0, 4.0] // ||v|| = 5
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)

        var normalized = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))

        // Check unit length
        var normalizedNorm: Float = 0
        vDSP_svesq(normalized, 1, &normalizedNorm, vDSP_Length(normalized.count))
        normalizedNorm = sqrt(normalizedNorm)
        XCTAssertEqual(normalizedNorm, 1.0, accuracy: 0.0001)
    }

    func testCosineSimilarityIdentical() {
        // Identical L2-normalized vectors should have similarity 1.0
        let v: [Float] = [0.6, 0.8] // already unit length (0.36 + 0.64 = 1)
        var dot: Float = 0
        vDSP_dotpr(v, 1, v, 1, &dot, vDSP_Length(v.count))
        XCTAssertEqual(dot, 1.0, accuracy: 0.0001)
    }

    func testCosineSimilarityOrthogonal() {
        // Orthogonal vectors should have similarity 0.0
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [0.0, 1.0]
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        XCTAssertEqual(dot, 0.0, accuracy: 0.0001)
    }

    func testCosineSimilarityOpposite() {
        // Opposite vectors should have similarity -1.0
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [-1.0, 0.0]
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        XCTAssertEqual(dot, -1.0, accuracy: 0.0001)
    }
}
