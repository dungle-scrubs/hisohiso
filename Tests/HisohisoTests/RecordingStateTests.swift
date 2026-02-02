import XCTest
@testable import Hisohiso

final class RecordingStateTests: XCTestCase {
    func testStateEquality() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertEqual(RecordingState.recording, RecordingState.recording)
        XCTAssertEqual(RecordingState.transcribing, RecordingState.transcribing)
        XCTAssertEqual(RecordingState.error(message: "test"), RecordingState.error(message: "test"))
        XCTAssertNotEqual(RecordingState.error(message: "a"), RecordingState.error(message: "b"))
        XCTAssertNotEqual(RecordingState.idle, RecordingState.recording)
    }

    @MainActor
    func testStateManagerTransitions() async {
        let manager = RecordingStateManager()

        XCTAssertTrue(manager.isIdle)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isTranscribing)
        XCTAssertFalse(manager.hasError)

        manager.setRecording()
        XCTAssertFalse(manager.isIdle)
        XCTAssertTrue(manager.isRecording)

        manager.setTranscribing()
        XCTAssertFalse(manager.isRecording)
        XCTAssertTrue(manager.isTranscribing)

        manager.setError("test error")
        XCTAssertFalse(manager.isTranscribing)
        XCTAssertTrue(manager.hasError)

        manager.setIdle()
        XCTAssertTrue(manager.isIdle)
        XCTAssertFalse(manager.hasError)
    }

    @MainActor
    func testRetryCallback() async {
        let manager = RecordingStateManager()
        var retryCalled = false

        manager.onRetry = {
            retryCalled = true
        }

        manager.retry()
        XCTAssertTrue(retryCalled)
    }
}
