@testable import Hisohiso
import XCTest

final class CloudTranscriptionErrorTests: XCTestCase {
    func testInvalidAPIKeyDescriptionIsStable() {
        XCTAssertEqual(CloudTranscriptionError.invalidAPIKey.errorDescription, "Invalid API key")
    }

    func testAPIErrorDescriptionUsesSanitizedFields() {
        let error = CloudTranscriptionError.apiError(
            statusCode: 500,
            provider: "Test Provider",
            code: "server_error"
        )

        XCTAssertEqual(
            error.errorDescription,
            "Test Provider API error (HTTP 500, code: server_error)"
        )
    }

    func testSanitizedAPIErrorDoesNotExposeRawResponseBody() {
        let body = Data("{\"error\":{\"message\":\"secret token sk-live\",\"code\":\"server_overloaded\"}}".utf8)
        let error = CloudTranscriptionError.sanitizedAPIError(
            statusCode: 500,
            provider: "Test Provider",
            responseBody: body
        )

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("server_overloaded"))
        XCTAssertFalse(description.contains("secret token"))
        XCTAssertFalse(description.contains("sk-live"))
    }

    func testSanitizedAPIErrorFallsBackToHTTPStatusCode() {
        let body = Data("raw upstream failure with private details".utf8)
        let error = CloudTranscriptionError.sanitizedAPIError(
            statusCode: 503,
            provider: "Test Provider",
            responseBody: body
        )

        XCTAssertEqual(
            error.errorDescription,
            "Test Provider API error (HTTP 503, code: http_503)"
        )
    }
}
