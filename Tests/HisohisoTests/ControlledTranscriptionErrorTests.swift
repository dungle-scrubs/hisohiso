@testable import Hisohiso
import XCTest

final class ControlledTranscriptionErrorTests: XCTestCase {
    func testErrorDescriptionsAreStable() {
        XCTAssertEqual(ControlledTranscriptionError.notRecording.errorDescription, "Not currently recording")
        XCTAssertEqual(ControlledTranscriptionError.noAudioCaptured.errorDescription, "No audio captured")
        XCTAssertEqual(ControlledTranscriptionError.audioTooShort.errorDescription, "Audio too short for transcription")
        XCTAssertEqual(ControlledTranscriptionError.emptyTranscription.errorDescription, "No transcription produced")
        XCTAssertEqual(ControlledTranscriptionError.voiceVerificationFailed.errorDescription, "Voice verification failed")

        let insertion = ControlledTranscriptionError.textInsertionFailed("AX error")
        XCTAssertEqual(insertion.errorDescription, "Text insertion failed: AX error")

        let transcription = ControlledTranscriptionError.transcriptionFailed("timeout")
        XCTAssertEqual(transcription.errorDescription, "Transcription failed: timeout")
    }
}
