@testable import Hisohiso
import XCTest

final class ControlProtocolTests: XCTestCase {
    func testControlRequestMakeGeneratesID() {
        let request = ControlRequest.make(method: .ping)
        XCTAssertFalse(request.id.isEmpty)
        XCTAssertEqual(request.method, .ping)
        XCTAssertNil(request.params)
    }

    func testControlStateMapsRecordingStateValues() {
        XCTAssertEqual(ControlState(from: .idle), .idle)
        XCTAssertEqual(ControlState(from: .recording), .recording)
        XCTAssertEqual(ControlState(from: .transcribing), .transcribing)
        XCTAssertEqual(ControlState(from: .error(message: "boom")), .error)
    }

    func testControlResponseSuccessFactory() {
        let response = ControlResponse.success(
            id: "req-1",
            result: ControlResult(
                state: .idle,
                message: nil,
                text: "hello",
                model: "parakeet-tdt-0.6b-v2"
            )
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "req-1")
        XCTAssertEqual(response.result?.text, "hello")
        XCTAssertNil(response.error)
    }

    func testControlResponseFailureFactory() {
        let response = ControlResponse.failure(id: "req-2", error: "bad request")

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "req-2")
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error, "bad request")
    }

    func testControlRequestRoundTripsJSON() throws {
        let request = ControlRequest(
            id: "req-3",
            method: .start,
            params: ControlRequestParams(model: "openai_whisper-base.en")
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: data)

        XCTAssertEqual(decoded.id, "req-3")
        XCTAssertEqual(decoded.method, .start)
        XCTAssertEqual(decoded.params?.model, "openai_whisper-base.en")
    }
}
