@testable import Hisohiso
import XCTest

final class WaveformConnectionStoreTests: XCTestCase {
    func testStartsDisconnectedAndUnavailable() {
        let store = WaveformConnectionStore()
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(store.isAvailable)
        XCTAssertEqual(store.latestStateCommand, "state idle")
    }

    func testConnectMarksConnectedAndAvailable() {
        var store = WaveformConnectionStore()
        store.connect(fd: 7)
        XCTAssertTrue(store.isConnected)
        XCTAssertTrue(store.isAvailable)
    }

    func testDisconnectReturnsFDAndClearsState() {
        var store = WaveformConnectionStore()
        store.connect(fd: 7)
        XCTAssertEqual(store.disconnect(), 7)
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(store.isAvailable)
        XCTAssertNil(store.disconnect())
    }

    func testRecordStateCommandUpdatesReplayValue() {
        var store = WaveformConnectionStore()
        store.recordStateCommand("state recording")
        XCTAssertEqual(store.latestStateCommand, "state recording")
    }
}
