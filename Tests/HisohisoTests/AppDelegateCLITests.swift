@testable import Hisohiso
import XCTest

final class AppDelegateCLITests: XCTestCase {
    func testMakeControlFailureResponseWrapsConnectErrorsWithStartupHint() {
        let response = AppDelegate.makeControlFailureResponse(
            requestID: "req-connect",
            error: .connectFailed("No such file or directory")
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "req-connect")
        XCTAssertNil(response.result)
        XCTAssertEqual(
            response.error,
            "Failed to connect to Hisohiso control socket: No such file or directory. Start Hisohiso first (open -a Hisohiso), then retry."
        )
    }

    func testMakeControlFailureResponsePassesThroughNonConnectErrors() {
        let response = AppDelegate.makeControlFailureResponse(
            requestID: "req-decode",
            error: .decodeFailed
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "req-decode")
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error, "Failed to decode control response")
    }
}
