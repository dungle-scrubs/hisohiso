@testable import Hisohiso
import XCTest

final class DictationFinalizationCoordinatorTests: XCTestCase {
    func testSuccessfulCursorInsertionSavesHistoryAndIdlesOnce() throws {
        let recorder = FinalizationRecorder()
        let coordinator = recorder.makeCoordinator()

        let result = coordinator.finishSuccess(rawText: "hello world", duration: 1.2, mode: .insertAtCursor, modelName: "Model")

        XCTAssertEqual(try result.get(), "Hello world")
        XCTAssertEqual(recorder.insertedText, ["Hello world"])
        XCTAssertEqual(recorder.savedText, ["Hello world"])
        XCTAssertEqual(recorder.idleCount, 1)
    }

    func testEmptyAudioFailureIdlesOnce() {
        let recorder = FinalizationRecorder()
        let coordinator = recorder.makeCoordinator()

        let result = coordinator.failIdle(.noAudioCaptured)

        guard case .failure(.noAudioCaptured) = result else {
            XCTFail("Expected noAudioCaptured")
            return
        }
        XCTAssertEqual(recorder.idleCount, 1)
    }

    func testVoiceVerificationFailureIdlesOnce() {
        let recorder = FinalizationRecorder()
        let coordinator = recorder.makeCoordinator()

        let result = coordinator.failIdle(.voiceVerificationFailed)

        guard case .failure(.voiceVerificationFailed) = result else {
            XCTFail("Expected voiceVerificationFailed")
            return
        }
        XCTAssertEqual(recorder.idleCount, 1)
    }

    func testInsertionFailureSetsErrorWithoutIdle() {
        let recorder = FinalizationRecorder(insertError: TestInsertionError())
        let coordinator = recorder.makeCoordinator()

        let result = coordinator.finishSuccess(rawText: "hello", duration: 1, mode: .insertAtCursor, modelName: "Model")

        guard case .failure(.textInsertionFailed) = result else {
            XCTFail("Expected insertion failure")
            return
        }
        XCTAssertEqual(recorder.idleCount, 0)
        XCTAssertEqual(recorder.errorMessages, ["Insert failed"])
    }

    func testExternalOutputModeDoesNotInsertText() throws {
        let recorder = FinalizationRecorder()
        let coordinator = recorder.makeCoordinator()

        let result = coordinator.finishSuccess(rawText: "external text", duration: 1, mode: .returnTextOnly, modelName: "Model")

        XCTAssertEqual(try result.get(), "External text")
        XCTAssertTrue(recorder.insertedText.isEmpty)
        XCTAssertEqual(recorder.savedText, ["External text"])
        XCTAssertEqual(recorder.idleCount, 1)
    }

    func testEveryIdleFailureExitSendsExactlyOneIdleTransition() {
        for error in [ControlledTranscriptionError.noAudioCaptured, .audioTooShort, .emptyTranscription, .voiceVerificationFailed] {
            let recorder = FinalizationRecorder()
            _ = recorder.makeCoordinator().failIdle(error)
            XCTAssertEqual(recorder.idleCount, 1)
        }
    }
}

private final class FinalizationRecorder {
    var idleCount = 0
    var errorMessages: [String] = []
    var savedText: [String] = []
    var insertedText: [String] = []
    let insertError: Error?

    init(insertError: Error? = nil) {
        self.insertError = insertError
    }

    func makeCoordinator() -> DictationFinalizationCoordinator {
        DictationFinalizationCoordinator(
            textFormatter: TextFormatter(),
            setIdle: { self.idleCount += 1 },
            setError: { self.errorMessages.append($0) },
            saveHistory: { text, _, _ in self.savedText.append(text) },
            insertText: { text in
                if let insertError = self.insertError { throw insertError }
                self.insertedText.append(text)
            }
        )
    }
}

private struct TestInsertionError: LocalizedError {
    var errorDescription: String? { "Insert failed" }
}
