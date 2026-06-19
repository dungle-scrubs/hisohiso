@testable import Hisohiso
import XCTest

final class AudioRecorderStateStoreTests: XCTestCase {
    func testInitialStateIsIdle() {
        let store = AudioRecorderStateStore()

        XCTAssertEqual(store.state(), .idle)
    }

    func testStateTransitionsAreSerialized() {
        let store = AudioRecorderStateStore()
        store.setState(.monitoring)
        store.setState(.recordingFromMonitoring)
        store.setState(.monitoring)

        XCTAssertEqual(store.state(), .monitoring)
    }

    func testDrainSamplesReturnsAndClearsCapturedSamples() {
        let store = AudioRecorderStateStore()
        store.appendSamples([1, 2, 3])

        XCTAssertEqual(store.drainSamples(), [1, 2, 3])
        XCTAssertEqual(store.drainSamples(), [])
    }

    func testRecentSamplesReturnsSuffix() {
        let store = AudioRecorderStateStore()
        store.appendSamples([1, 2, 3, 4])

        XCTAssertEqual(store.recentSamples(count: 2), [3, 4])
    }

    func testConcurrentSampleAccessIsSafe() {
        let store = AudioRecorderStateStore()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.hisohiso.tests.audio-state-store", attributes: .concurrent)

        for index in 0..<500 {
            group.enter()
            queue.async {
                if index.isMultiple(of: 3) {
                    store.appendSamples([Float(index)])
                } else if index % 3 == 1 {
                    _ = store.drainSamples()
                } else {
                    _ = store.recentSamples(count: 16)
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
    }
}
