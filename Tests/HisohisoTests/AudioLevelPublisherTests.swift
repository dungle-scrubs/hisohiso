import XCTest
@testable import Hisohiso

@MainActor
final class AudioLevelPublisherTests: XCTestCase {
    func testTickPublishesCalculatedLevelsFromInjectedSamples() {
        var published: [[UInt8]] = []
        let publisher = AudioLevelPublisher(sampleProvider: { [0.1, 0.2, 0.3] }, levelSink: { published.append($0) }, autoStop: {})

        publisher.tick()

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published[0], AudioLevelPublisher.calculateAudioLevels(from: [0.1, 0.2, 0.3]))
    }

    func testWakeWordSilenceAutoStopUsesInjectedTicks() {
        var stops = 0
        let publisher = AudioLevelPublisher(sampleProvider: { [0, 0, 0] }, levelSink: { _ in }, autoStop: { stops += 1 })
        publisher.start(isWakeWordTriggered: true)
        defer { publisher.stop() }

        for _ in 0..<(AppConstants.silenceGracePeriodFrames + AppConstants.silenceThresholdForStop) {
            publisher.tick()
        }

        XCTAssertGreaterThanOrEqual(stops, 1)
    }

    func testClearLevelsPublishesZeroWaveform() {
        var published: [UInt8] = []
        let publisher = AudioLevelPublisher(sampleProvider: { [] }, levelSink: { published = $0 }, autoStop: {})

        publisher.clearLevels()

        XCTAssertEqual(published, [UInt8](repeating: 0, count: AppConstants.waveformBarCount))
    }
}
