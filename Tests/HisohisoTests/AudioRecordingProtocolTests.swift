@testable import Hisohiso
import XCTest

/// Tests that both recorder implementations conform to AudioRecording protocol.
///
/// We can't test actual audio capture in unit tests (requires hardware),
/// but we can verify protocol conformance and basic contract behavior.
final class AudioRecordingProtocolTests: XCTestCase {
    func testAudioRecorderConformsToProtocol() {
        let recorder: AudioRecording = AudioRecorder()
        XCTAssertNotNil(recorder, "AudioRecorder should conform to AudioRecording")
    }

    func testAudioKitRecorderConformsToProtocol() {
        let recorder: AudioRecording = AudioKitRecorder()
        XCTAssertNotNil(recorder, "AudioKitRecorder should conform to AudioRecording")
    }

    func testGetRecentSamplesReturnsEmptyWhenNotRecording() {
        let recorder: AudioRecording = AudioRecorder()
        let samples = recorder.getRecentSamples(count: 100)
        XCTAssertTrue(samples.isEmpty, "Should return empty when not recording")
    }

    func testStopRecordingReturnsEmptyWhenNotRecording() {
        let recorder: AudioRecording = AudioRecorder()
        let samples = recorder.stopRecording()
        XCTAssertTrue(samples.isEmpty, "Should return empty when not recording")
    }

    func testCancelRecordingIsNoOpWhenNotRecording() {
        let recorder: AudioRecording = AudioRecorder()
        // Should not crash when cancelling without recording
        recorder.cancelRecording()
    }
}
