@testable import Hisohiso
import XCTest

/// Tests for `DictationController` using the injected `TranscribingService` and
/// `VoiceVerifying` seams.
///
/// ## Coverage note
/// The transcription-result guards, the `TranscriberError` end-state mapping,
/// and the voice-verification block/proceed/fail-closed branches all live
/// downstream of `activeRecorder.stopRecording()`. `DictationController` hard-wires
/// its recorders (`let audioRecorder = AudioRecorder()`), so tests cannot inject
/// non-empty audio samples through the public surface: every stop with the idle
/// real recorder drains to `[]` and short-circuits at the empty-audio guard.
/// Reaching those branches deterministically requires an `AudioRecording`
/// injection point on `DictationController.init`, which is out of scope here.
/// The finalization side of the mapping (failIdle/finishSuccess) is covered by
/// `DictationFinalizationCoordinatorTests`; the fakes below are complete so the
/// remaining branches are trivial to add once a recorder seam exists.
@MainActor
final class DictationControllerTests: XCTestCase {
    // MARK: - Not recording early return

    func testStopWhenIdleReturnsNotRecording() async {
        let context = makeController()

        let result = await context.controller.stopRecordingForExternalControl()

        assertFailure(result, .notRecording)
        XCTAssertTrue(context.controller.isIdle)
    }

    func testStopWhileTranscribingReturnsNotRecording() async {
        let context = makeController()
        context.controller.stateManager.setTranscribing()

        let result = await context.controller.stopRecordingForExternalControl()

        assertFailure(result, .notRecording)
    }

    func testStopWhileInErrorStateReturnsNotRecording() async {
        let context = makeController()
        context.controller.stateManager.setError("boom")

        let result = await context.controller.stopRecordingForExternalControl()

        assertFailure(result, .notRecording)
    }

    func testVoidStopWhenIdleLeavesStateIdle() async {
        let context = makeController()

        await context.controller.stopRecordingAndTranscribe()

        XCTAssertTrue(context.controller.isIdle)
    }

    // MARK: - Empty-audio guard

    func testEmptyAudioFailsIdleWithNoAudioCaptured() async {
        let context = makeController()
        // Force the FSM into recording so the stop guard passes; the real idle
        // recorder drains no samples, exercising the empty-audio guard.
        context.controller.stateManager.setRecording()

        let result = await context.controller.stopRecordingForExternalControl()

        assertFailure(result, .noAudioCaptured)
        XCTAssertTrue(context.controller.isIdle, "Empty-audio exit must return to idle")
    }

    func testEmptyAudioNeverInvokesTranscriberOrVerifier() async {
        let context = makeController()
        context.controller.stateManager.setRecording()

        _ = await context.controller.stopRecordingForExternalControl()

        XCTAssertTrue(context.transcriber.transcribeInputs.isEmpty)
        XCTAssertEqual(context.verifier.verifyCount, 0)
    }

    // MARK: - Cancel

    func testCancelForExternalControlReturnsToIdle() {
        let context = makeController()
        context.controller.stateManager.setRecording()

        context.controller.cancelRecordingForExternalControl()

        XCTAssertTrue(context.controller.isIdle)
    }

    func testCancelForExternalControlWhenIdleIsNoOp() {
        let context = makeController()

        context.controller.cancelRecordingForExternalControl()

        XCTAssertTrue(context.controller.isIdle)
    }

    // MARK: - reloadSelectedModel (injected transcriber seam)

    func testReloadSelectedModelInitializesInjectedTranscriber() async throws {
        let context = makeController(selectedModel: .whisperTiny)

        try await context.controller.reloadSelectedModel()

        XCTAssertEqual(context.transcriber.initializedModels, [.whisperTiny])
    }

    func testReloadSelectedModelThrowsWhenBusy() async {
        let context = makeController()
        context.controller.stateManager.setRecording()

        do {
            try await context.controller.reloadSelectedModel()
            XCTFail("Expected cannotChangeModelWhileBusy")
        } catch let error as DictationError {
            XCTAssertEqual(error, .cannotChangeModelWhileBusy)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(context.transcriber.initializedModels.isEmpty)
    }

    func testReloadSelectedModelPropagatesTranscriberError() async {
        let context = makeController()
        context.transcriber.setInitializeError(TranscriberError.modelNotFound("x"))

        do {
            try await context.controller.reloadSelectedModel()
            XCTFail("Expected the transcriber error to propagate")
        } catch let error as TranscriberError {
            guard case .modelNotFound = error else {
                return XCTFail("Unexpected TranscriberError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private struct Context {
        let controller: DictationController
        let transcriber: FakeTranscribingService
        let verifier: FakeVoiceVerifying
    }

    private func makeController(
        selectedModel: TranscriptionModel = .defaultModel,
        verifier: FakeVoiceVerifying = FakeVoiceVerifying()
    ) -> Context {
        let transcriber = FakeTranscribingService()
        let modelManager = ModelManager()
        modelManager.selectedModel = selectedModel
        let controller = DictationController(
            modelManager: modelManager,
            hotkeyManager: nil,
            mediaPlaybackCoordinator: MediaPlaybackCoordinator(controller: NoopMediaController()),
            transcriber: transcriber,
            voiceVerifier: verifier
        )
        // Force the AVAudioEngine backend so no test spins up AudioKit; both
        // backends return [] when idle, so behavior is identical either way.
        controller.useAudioKit = false
        return Context(controller: controller, transcriber: transcriber, verifier: verifier)
    }

    private func assertFailure(
        _ result: Result<String, ControlledTranscriptionError>,
        _ expected: ControlledTranscriptionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected failure \(expected), got success", file: file, line: line)
        case let .failure(error):
            XCTAssertEqual(
                error.errorDescription,
                expected.errorDescription,
                file: file,
                line: line
            )
        }
    }
}

// MARK: - Fakes

/// In-memory `TranscribingService` that records calls and returns configured
/// outcomes. Thread-safe because protocol methods are `nonisolated async` and
/// may run off the main actor.
private final class FakeTranscribingService: TranscribingService, @unchecked Sendable {
    private let lock = NSLock()
    private var _initializedModels: [TranscriptionModel] = []
    private var _transcribeInputs: [[Float]] = []
    private var _initializeError: Error?
    private var _transcribeError: Error?
    private var _transcribeResult = "transcribed text"

    var initializedModels: [TranscriptionModel] { lock.withLock { _initializedModels } }
    var transcribeInputs: [[Float]] { lock.withLock { _transcribeInputs } }

    func setInitializeError(_ error: Error?) { lock.withLock { _initializeError = error } }
    func setTranscribeError(_ error: Error?) { lock.withLock { _transcribeError = error } }
    func setTranscribeResult(_ text: String) { lock.withLock { _transcribeResult = text } }

    func initialize(model: TranscriptionModel) async throws {
        try lock.withLock {
            _initializedModels.append(model)
            if let error = _initializeError { throw error }
        }
    }

    func transcribe(_ audioSamples: [Float]) async throws -> String {
        try lock.withLock {
            _transcribeInputs.append(audioSamples)
            if let error = _transcribeError { throw error }
            return _transcribeResult
        }
    }
}

/// In-memory `VoiceVerifying` that returns a configured result or throws.
private final class FakeVoiceVerifying: VoiceVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var _isEnabled: Bool
    private var _isEnrolled: Bool
    private var _result: VerificationResult
    private var _verifyError: Error?
    private var _verifyCount = 0

    init(
        isEnabled: Bool = false,
        isEnrolled: Bool = false,
        result: VerificationResult = VerificationResult(isMatch: true, similarity: 1, reason: .matched),
        verifyError: Error? = nil
    ) {
        _isEnabled = isEnabled
        _isEnrolled = isEnrolled
        _result = result
        _verifyError = verifyError
    }

    var isEnabled: Bool { lock.withLock { _isEnabled } }
    var isEnrolled: Bool { lock.withLock { _isEnrolled } }
    var verifyCount: Int { lock.withLock { _verifyCount } }

    func verify(audioSamples _: [Float]) async throws -> VerificationResult {
        try lock.withLock {
            _verifyCount += 1
            if let error = _verifyError { throw error }
            return _result
        }
    }
}

/// Media controller that pauses/resumes nothing, keeping tests off AppleScript.
@MainActor
private final class NoopMediaController: MediaPlaybackControlling {
    func pausePlayingMedia() async -> Set<MediaPlaybackTarget> { [] }
    func resumeMedia(_: Set<MediaPlaybackTarget>) {}
}
