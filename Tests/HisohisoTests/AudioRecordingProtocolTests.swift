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

    func testConcurrentStopCancelAndRecentSamplesAreSafeWhenIdle() {
        let recorder: AudioRecording = AudioRecorder()
        let iterations = 200
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.hisohiso.tests.audio-race", attributes: .concurrent)

        for index in 0..<iterations {
            group.enter()
            queue.async {
                switch index % 3 {
                case 0:
                    _ = recorder.stopRecording()
                case 1:
                    recorder.cancelRecording()
                default:
                    _ = recorder.getRecentSamples(count: 128)
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
    }

    func testPauseResumeAndStopAreSafeWhenNotMonitoring() {
        let recorder = AudioRecorder()
        recorder.pauseMonitoring()
        recorder.resumeMonitoring()
        XCTAssertTrue(recorder.stopRecording().isEmpty)
    }
}
