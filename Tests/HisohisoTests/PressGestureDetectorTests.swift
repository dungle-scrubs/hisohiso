@testable import Hisohiso
import XCTest

@MainActor
final class PressGestureDetectorTests: XCTestCase {
    private let threshold: TimeInterval = 0.05

    private func makeDetector() -> (PressGestureDetector, Recorder) {
        let recorder = Recorder()
        let detector = PressGestureDetector(holdThreshold: threshold)
        detector.onTap = { recorder.events.append("tap") }
        detector.onHoldStart = { recorder.events.append("holdStart") }
        detector.onHoldEnd = { recorder.events.append("holdEnd") }
        return (detector, recorder)
    }

    private final class Recorder {
        var events: [String] = []
    }

    private func settle(_ multiple: Double = 2) async throws {
        try await Task.sleep(for: .seconds(threshold * multiple))
    }

    func testQuickPressReleaseIsTap() async throws {
        let (detector, recorder) = makeDetector()
        detector.press()
        detector.release()
        try await settle()
        XCTAssertEqual(recorder.events, ["tap"])
        XCTAssertFalse(detector.isPressed)
        XCTAssertFalse(detector.isHolding)
    }

    func testLongPressIsHoldThenHoldEnd() async throws {
        let (detector, recorder) = makeDetector()
        detector.press()
        try await settle()
        XCTAssertEqual(recorder.events, ["holdStart"])
        XCTAssertTrue(detector.isHolding)
        detector.release()
        XCTAssertEqual(recorder.events, ["holdStart", "holdEnd"])
        XCTAssertFalse(detector.isPressed)
    }

    func testRepeatedPressWhileDownIsIgnored() async throws {
        let (detector, recorder) = makeDetector()
        detector.press()
        detector.press()
        detector.press()
        try await settle()
        detector.release()
        XCTAssertEqual(recorder.events, ["holdStart", "holdEnd"])
    }

    func testReleaseWithoutPressDoesNothing() {
        let (detector, recorder) = makeDetector()
        detector.release()
        XCTAssertEqual(recorder.events, [])
    }

    func testTapThenImmediateSecondPressDoesNotInheritStaleHoldTimer() async throws {
        let (detector, recorder) = makeDetector()
        detector.press()
        detector.release()
        detector.press()
        // Shorter than the threshold measured from the second press, longer than
        // the remainder of the first press's timer would have been.
        try await Task.sleep(for: .seconds(threshold * 0.5))
        detector.release()
        try await settle()
        XCTAssertEqual(recorder.events, ["tap", "tap"])
    }

    func testResetDropsPressWithoutGesture() async throws {
        let (detector, recorder) = makeDetector()
        detector.press()
        detector.reset()
        try await settle()
        detector.release()
        XCTAssertEqual(recorder.events, [])
        XCTAssertFalse(detector.isPressed)
    }
}
