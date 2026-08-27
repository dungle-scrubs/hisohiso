@testable import Hisohiso
import XCTest

@MainActor
final class VoiceEnrollmentControllerTests: XCTestCase {
    func testManualStopEnrollsCapturedSample() async {
        let verifier = RecordingVoiceEnrollmentVerifier()
        let recorder = StubAudioRecording(samples: [validSample()])
        let controller = VoiceEnrollmentController(
            verifier: verifier,
            recorderFactory: { recorder },
            sampleDuration: 60
        )

        controller.start()
        controller.stop()
        await verifier.waitForEnrollment()
        await controller.awaitEnrollment()

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(verifier.enrolledSampleCounts, [1])
        XCTAssertEqual(controller.status, .completed)
    }

    func testDebugInfoSnapshotsEnrollmentState() {
        let verifier = SuspendedVoiceEnrollmentVerifier()
        let recorder = StubAudioRecording(samples: [validSample()])
        let controller = VoiceEnrollmentController(
            verifier: verifier,
            recorderFactory: { recorder },
            sampleDuration: 60,
            debugLogging: true
        )

        XCTAssertEqual(
            controller.debugInfo(),
            VoiceEnrollmentController.DebugInfo(
                sessionID: 0,
                status: .idle,
                capturedSampleCount: 0,
                isRecording: false,
                hasRecorder: false,
                hasEnrollmentTask: false
            )
        )

        controller.start()
        XCTAssertEqual(controller.debugInfo().status, .recording(sampleCount: 0))
        XCTAssertTrue(controller.debugInfo().isRecording)
        XCTAssertTrue(controller.debugInfo().hasRecorder)

        controller.stop()
        XCTAssertEqual(controller.debugInfo().status, .processing)
        XCTAssertTrue(controller.debugInfo().hasEnrollmentTask)

        controller.cancel()
        XCTAssertEqual(controller.debugInfo().status, .idle)
        XCTAssertFalse(controller.debugInfo().hasEnrollmentTask)
    }

    func testInvalidManualStopFailsWithTypedReason() {
        let verifier = RecordingVoiceEnrollmentVerifier()
        let recorder = StubAudioRecording(samples: [[0.1]])
        let controller = VoiceEnrollmentController(
            verifier: verifier,
            recorderFactory: { recorder },
            sampleDuration: 60
        )

        controller.start()
        controller.stop()

        XCTAssertEqual(controller.status, .failed(.noAudioCaptured))
        XCTAssertEqual(controller.debugInfo().capturedSampleCount, 0)
    }

    func testAutomaticCompletionDoesNotStopRecorderTwice() async {
        let verifier = RecordingVoiceEnrollmentVerifier()
        let recorder = StubAudioRecording(samples: [validSample(), validSample(), validSample()])
        let controller = VoiceEnrollmentController(
            verifier: verifier,
            recorderFactory: { recorder },
            sampleDuration: 0.01
        )

        controller.start()
        await verifier.waitForEnrollment()
        await controller.awaitEnrollment()

        XCTAssertEqual(recorder.startCount, 3)
        XCTAssertEqual(recorder.stopCount, 3)
        XCTAssertEqual(verifier.enrolledSampleCounts, [3])
        XCTAssertEqual(controller.status, .completed)
    }

    func testCancelSuppressesStaleEnrollmentResult() async throws {
        let verifier = SuspendedVoiceEnrollmentVerifier()
        let recorder = StubAudioRecording(samples: [validSample()])
        let controller = VoiceEnrollmentController(
            verifier: verifier,
            recorderFactory: { recorder },
            sampleDuration: 60
        )

        controller.start()
        controller.stop()
        await verifier.waitUntilStarted()
        controller.cancel()
        verifier.complete()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(controller.status, .idle)
    }
}

private final class StubAudioRecording: AudioRecording {
    private let samples: [[Float]]
    private var sampleIndex = 0

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init(samples: [[Float]]) {
        self.samples = samples
    }

    func startRecording() throws {
        startCount += 1
    }

    func stopRecording() -> [Float] {
        stopCount += 1
        guard sampleIndex < samples.count else { return [] }
        defer { sampleIndex += 1 }
        return samples[sampleIndex]
    }

    func cancelRecording() {
        cancelCount += 1
    }

    func getRecentSamples(count _: Int) -> [Float] {
        []
    }
}

private final class RecordingVoiceEnrollmentVerifier: VoiceEnrollmentVerifying, @unchecked Sendable {
    private(set) var enrolledSampleCounts: [Int] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func enroll(with samples: [[Float]]) async throws -> [Float] {
        enrolledSampleCounts.append(samples.count)
        continuations.forEach { $0.resume() }
        continuations = []
        return []
    }

    func waitForEnrollment() async {
        if !enrolledSampleCounts.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private final class SuspendedVoiceEnrollmentVerifier: VoiceEnrollmentVerifying, @unchecked Sendable {
    private var enrollmentContinuation: CheckedContinuation<[Float], Error>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func enroll(with samples: [[Float]]) async throws -> [Float] {
        startContinuations.forEach { $0.resume() }
        startContinuations = []
        return try await withCheckedThrowingContinuation { continuation in
            enrollmentContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if enrollmentContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func complete() {
        enrollmentContinuation?.resume(returning: [])
        enrollmentContinuation = nil
    }
}

private func validSample() -> [Float] {
    [Float](repeating: 0.1, count: VoiceVerifier.minSamplesForVerification)
}
