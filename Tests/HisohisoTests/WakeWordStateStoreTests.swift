@testable import Hisohiso
import XCTest

final class WakeWordStateStoreTests: XCTestCase {
    func testStartStopRestartListeningTransitions() {
        let store = WakeWordStateStore()

        XCTAssertFalse(store.isListening())
        store.setListening(true)
        XCTAssertTrue(store.isListening())
        store.setListening(false)
        store.resetBuffers()
        XCTAssertFalse(store.isListening())
        store.setListening(true)
        XCTAssertTrue(store.isListening())
    }

    func testSpeechThenSilenceProducesProcessingSamples() {
        let store = WakeWordStateStore()
        store.setListening(true)

        let speech = store.ingest(
            samples: [0.5, 0.5],
            isSpeechFrame: true,
            silenceThreshold: 2,
            preBufferFrames: 2,
            maxBufferSamples: 10
        )
        XCTAssertNotEqual(speech, .process(samples: [0.5, 0.5]))

        _ = store.ingest(samples: [0, 0], isSpeechFrame: false, silenceThreshold: 2, preBufferFrames: 2, maxBufferSamples: 10)
        let result = store.ingest(samples: [0, 0], isSpeechFrame: false, silenceThreshold: 2, preBufferFrames: 2, maxBufferSamples: 10)

        guard case let .process(samples) = result else {
            XCTFail("Expected samples to process")
            return
        }
        XCTAssertFalse(samples.isEmpty)
    }
}
