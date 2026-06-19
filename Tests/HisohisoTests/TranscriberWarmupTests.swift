@testable import Hisohiso
import XCTest

final class TranscriberWarmupTests: XCTestCase {
    func testWarmupFailureErrorDescriptionIncludesModelAndBackend() {
        let underlying = NSError(domain: "Warmup", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let error = TranscriberError.warmupFailed(
            model: "openai_whisper-base.en",
            backend: "whisper",
            underlying: underlying
        )

        XCTAssertEqual(
            error.errorDescription,
            "Warmup failed for openai_whisper-base.en (whisper): boom"
        )
    }

    func testTranscriberDoesNotSilenceWarmupFailuresWithTryQuestionMark() throws {
        let source = try String(contentsOfFile: "Sources/Hisohiso/Transcriber.swift", encoding: .utf8)

        XCTAssertFalse(source.contains("try? await kit.transcribe"))
        XCTAssertFalse(source.contains("try? await asrManager?.transcribe"))
    }
}
