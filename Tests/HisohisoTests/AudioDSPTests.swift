import XCTest
@testable import Hisohiso

final class AudioDSPTests: XCTestCase {
    // MARK: - Resample

    func testResampleDownsample() {
        // 48kHz to 16kHz = 3:1 ratio
        let input = [Float](repeating: 0.5, count: 4800)
        let output = AudioDSP.resample(input, from: 48000, to: 16000)
        XCTAssertEqual(output.count, 1600)
    }

    func testResampleUpsample() {
        // 8kHz to 16kHz = 1:2 ratio
        let input = [Float](repeating: 0.5, count: 800)
        let output = AudioDSP.resample(input, from: 8000, to: 16000)
        XCTAssertEqual(output.count, 1600)
    }

    func testResampleSameRate() {
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let output = AudioDSP.resample(input, from: 16000, to: 16000)
        XCTAssertEqual(output.count, input.count)
    }

    func testResampleEmptyInput() {
        let output = AudioDSP.resample([], from: 48000, to: 16000)
        XCTAssertTrue(output.isEmpty)
    }

    func testResamplePreservesSignalCharacteristics() {
        // A simple ramp signal should roughly preserve its shape
        let input = (0..<480).map { Float($0) / 480.0 }
        let output = AudioDSP.resample(input, from: 48000, to: 16000)
        // Output should start near 0 and end near 1
        XCTAssertLessThan(output.first ?? 1, 0.1)
        XCTAssertGreaterThan(output.last ?? 0, 0.9)
    }

    // MARK: - Normalize

    func testNormalizeScalesToTargetPeak() {
        // Signal with peak at 0.5 should be scaled to 0.9 (default)
        let input: [Float] = [0.0, 0.25, 0.5, -0.5, -0.25]
        let output = AudioDSP.normalize(input)

        // Find peak of output
        let peak = output.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 0.9, accuracy: 0.01)
    }

    func testNormalizeCustomTargetPeak() {
        let input: [Float] = [0.0, 0.5, -0.5]
        let output = AudioDSP.normalize(input, targetPeak: 0.5)
        let peak = output.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 0.5, accuracy: 0.01)
    }

    func testNormalizeRespectsMaxGain() {
        // Very quiet signal (peak 0.002) with targetPeak 0.9 would need 450x gain
        // maxGain caps at 20x by default
        let input: [Float] = [0.0, 0.002, -0.002]
        let output = AudioDSP.normalize(input)
        let peak = output.map { abs($0) }.max() ?? 0
        // With 20x gain: 0.002 * 20 = 0.04
        XCTAssertEqual(peak, 0.04, accuracy: 0.001)
    }

    func testNormalizeSilencePassthrough() {
        // Near-silence (peak < 0.001) should pass through unchanged
        let input: [Float] = [0.0, 0.0001, -0.0001]
        let output = AudioDSP.normalize(input)
        XCTAssertEqual(output, input)
    }

    func testNormalizeEmptyInput() {
        let output = AudioDSP.normalize([])
        XCTAssertTrue(output.isEmpty)
    }

    func testNormalizeAlreadyAtTarget() {
        // Signal already at 0.9 peak should be unchanged
        let input: [Float] = [0.0, 0.9, -0.9]
        let output = AudioDSP.normalize(input)
        XCTAssertEqual(output[1], 0.9, accuracy: 0.01)
    }

    func testNormalizePreservesZeroCrossings() {
        // Normalization should not change sign of any sample
        let input: [Float] = [-0.3, -0.1, 0.0, 0.1, 0.3]
        let output = AudioDSP.normalize(input)
        for (i, o) in zip(input, output) {
            if i > 0 { XCTAssertGreaterThan(o, 0) }
            else if i < 0 { XCTAssertLessThan(o, 0) }
            else { XCTAssertEqual(o, 0, accuracy: 0.0001) }
        }
    }
}
