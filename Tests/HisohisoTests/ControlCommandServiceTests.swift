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

    private func makeService() -> ControlCommandService {
        makeService(dictation: FakeDictationControl())
    }

    private func makeService(dictation: FakeDictationControl?) -> ControlCommandService {
        let modelManager = ModelManager()
        let modelSelectionController = ModelSelectionController(modelManager: modelManager)
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

    var isControlIdle: Bool {
        controlRecordingState == .idle
    }

    var isControlRecording: Bool {
        controlRecordingState == .recording
    }

    func startControlRecording() async {
        didStart = true
        controlRecordingState = .recording
    }

    func stopControlRecording() async -> Result<String, ControlledTranscriptionError> {
        controlRecordingState = .idle
        return .success("Transcript")
    }

    func cancelControlRecording() {
        controlRecordingState = .idle
    }
}
