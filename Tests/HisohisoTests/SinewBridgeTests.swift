@testable import Hisohiso
import XCTest

final class SinewBridgeTests: XCTestCase {
    // MARK: - Audio Level Calculation

    func testCalculateAudioLevelsReturnsSevenBars() {
        let samples = [Float](repeating: 0.5, count: 1600)
        let levels = SinewBridge.calculateAudioLevels(from: samples)
        XCTAssertEqual(levels.count, 7)
    }

    func testCalculateAudioLevelsEmptyInput() {
        let levels = SinewBridge.calculateAudioLevels(from: [])
        XCTAssertEqual(levels.count, 7)
        for level in levels {
            XCTAssertEqual(level, 0)
        }
    }

    func testCalculateAudioLevelsSilence() {
        let samples = [Float](repeating: 0.0, count: 1600)
        let levels = SinewBridge.calculateAudioLevels(from: samples)
        for level in levels {
            XCTAssertEqual(level, 0, "Silent audio should produce zero levels")
        }
    }

    func testCalculateAudioLevelsLoudSignal() {
        // Full-scale signal should produce high levels
        let samples = [Float](repeating: 0.8, count: 1600)
        let levels = SinewBridge.calculateAudioLevels(from: samples)

        for level in levels {
            XCTAssertGreaterThan(level, 0, "Loud signal should produce non-zero levels")
        }
    }

    func testCalculateAudioLevelsCapsAtHundred() {
        // Extremely loud signal should cap at 100
        let samples = [Float](repeating: 1.0, count: 1600)
        let levels = SinewBridge.calculateAudioLevels(from: samples)

        for level in levels {
            XCTAssertLessThanOrEqual(level, 100, "Levels should not exceed 100")
        }
    }

    func testCalculateAudioLevelsVaryingInput() {
        // First half loud, second half silent
        var samples = [Float](repeating: 0.5, count: 800)
        samples.append(contentsOf: [Float](repeating: 0.0, count: 800))

        let levels = SinewBridge.calculateAudioLevels(from: samples)

        // First few bars should be louder than last few
        let firstHalfAvg = levels[0..<3].map(Int.init).reduce(0, +) / 3
        let secondHalfAvg = levels[4..<7].map(Int.init).reduce(0, +) / 3
        XCTAssertGreaterThan(firstHalfAvg, secondHalfAvg)
    }

    func testCalculateAudioLevelsSmallInput() {
        // Fewer samples than bars
        let samples: [Float] = [0.5, 0.3, 0.1]
        let levels = SinewBridge.calculateAudioLevels(from: samples)
        XCTAssertEqual(levels.count, 7)
    }
}
