@testable import Hisohiso
import XCTest

@MainActor
final class ControlCommandServiceTests: XCTestCase {
    func testHandlesPingWithoutSocketTransport() async {
        let service = makeService()
        let request = ControlRequest(id: "req-ping", method: .ping, params: nil)

        let response = await service.handle(request)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "req-ping")
        XCTAssertEqual(response.result?.state, .idle)
    }

    func testHandlesStartWithoutSocketTransport() async {
        let dictation = FakeDictationControl()
        let service = makeService(dictation: dictation)
        let request = ControlRequest(id: "req-start", method: .start, params: nil)

        let response = await service.handle(request)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "req-start")
        XCTAssertEqual(response.result?.state, .recording)
        XCTAssertTrue(dictation.didStart)
    }

    func testStatusFailsWhenDictationIsNotReady() async {
        let service = makeService(dictation: nil)
        let request = ControlRequest(id: "req-status", method: .status, params: nil)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Dictation controller not ready")
    }

    func testStopReturnsTranscriptOnSuccess() async {
        let dictation = FakeDictationControl()
        dictation.controlRecordingState = .recording
        let service = makeService(dictation: dictation)
        let request = ControlRequest(id: "req-stop", method: .stop, params: nil)

        let response = await service.handle(request)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "req-stop")
        XCTAssertEqual(response.result?.state, .idle)
        XCTAssertEqual(response.result?.text, "Transcript")
    }

    func testStopFailsWhenDictationIsNotReady() async {
        let service = makeService(dictation: nil)
        let request = ControlRequest(id: "req-stop", method: .stop, params: nil)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Dictation controller not ready")
    }

    func testCancelFailsWhenDictationIsNotReady() async {
        let service = makeService(dictation: nil)
        let request = ControlRequest(id: "req-cancel", method: .cancel, params: nil)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Dictation controller not ready")
    }

    func testStartFailsWhenRecorderIsBusy() async {
        let dictation = FakeDictationControl()
        dictation.controlRecordingState = .recording
        let service = makeService(dictation: dictation)
        let request = ControlRequest(id: "req-start", method: .start, params: nil)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Recorder is busy")
        XCTAssertFalse(dictation.didStart)
    }

    func testStartRejectsUnknownModel() async {
        let dictation = FakeDictationControl()
        let service = makeService(dictation: dictation)
        let params = ControlRequestParams(model: "totally-unknown-model")
        let request = ControlRequest(id: "req-start", method: .start, params: params)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Unknown model: totally-unknown-model")
        XCTAssertFalse(dictation.didStart)
    }

    func testStartFailsWhenModelSelectionThrows() async {
        let dictation = FakeDictationControl()
        let reloader = FakeModelReloader(isModelReloadAllowed: false)
        let service = makeService(dictation: dictation, reloader: reloader)
        let params = ControlRequestParams(model: TranscriptionModel.whisperTiny.rawValue)
        let request = ControlRequest(id: "req-start", method: .start, params: params)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(
            response.error,
            DictationError.cannotChangeModelWhileBusy.localizedDescription
        )
        XCTAssertFalse(dictation.didStart)
    }

    func testStartFailsWhenRecorderDoesNotStart() async {
        let dictation = FakeDictationControl()
        dictation.failsToStart = true
        let service = makeService(dictation: dictation)
        let request = ControlRequest(id: "req-start", method: .start, params: nil)

        let response = await service.handle(request)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Failed to start recording")
        XCTAssertTrue(dictation.didStart)
    }

    private func makeService() -> ControlCommandService {
        makeService(dictation: FakeDictationControl())
    }

    private func makeService(
        dictation: FakeDictationControl?,
        reloader: (any ModelReloading)? = nil
    ) -> ControlCommandService {
        let modelManager = ModelManager()
        let modelSelectionController = ModelSelectionController(modelManager: modelManager)
        if let reloader {
            modelSelectionController.attachReloader(reloader)
        }
        return ControlCommandService(
            modelSelectionController: modelSelectionController,
            dictationController: { dictation }
        )
    }
}

@MainActor
private final class FakeDictationControl: DictationControlHandling {
    var controlRecordingState: RecordingState = .idle
    var didStart = false

    /// When true, `startControlRecording` records the attempt but leaves the
    /// state unchanged so the post-start recording guard fails.
    var failsToStart = false

    var isControlIdle: Bool {
        controlRecordingState == .idle
    }

    var isControlRecording: Bool {
        controlRecordingState == .recording
    }

    func startControlRecording() async {
        didStart = true
        if !failsToStart {
            controlRecordingState = .recording
        }
    }

    func stopControlRecording() async -> Result<String, ControlledTranscriptionError> {
        controlRecordingState = .idle
        return .success("Transcript")
    }

    func cancelControlRecording() {
        controlRecordingState = .idle
    }
}

@MainActor
private final class FakeModelReloader: ModelReloading {
    var isModelReloadAllowed: Bool
    var reloadError: Error?
    private(set) var didReload = false

    init(isModelReloadAllowed: Bool = true, reloadError: Error? = nil) {
        self.isModelReloadAllowed = isModelReloadAllowed
        self.reloadError = reloadError
    }

    func reloadSelectedModel() async throws {
        didReload = true
        if let reloadError {
            throw reloadError
        }
    }
}
