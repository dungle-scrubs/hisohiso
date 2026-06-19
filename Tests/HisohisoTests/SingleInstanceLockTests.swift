import Foundation
@testable import Hisohiso
import XCTest

final class SingleInstanceLockTests: XCTestCase {
    func testSecondLockFailsWhileFirstLockIsHeld() throws {
        let lockURL = temporaryLockURL()
        let firstLock = try SingleInstanceLock(lockURL: lockURL)

        XCTAssertThrowsError(try SingleInstanceLock(lockURL: lockURL)) { error in
            XCTAssertEqual(
                error as? SingleInstanceLockError,
                .alreadyRunning(ownerPID: ProcessInfo.processInfo.processIdentifier)
            )
        }

        _ = firstLock
    }

    func testLockCanBeReacquiredAfterFirstLockIsReleased() throws {
        let lockURL = temporaryLockURL()

        do {
            _ = try SingleInstanceLock(lockURL: lockURL)
        }

        XCTAssertNoThrow(try SingleInstanceLock(lockURL: lockURL))
    }

    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.hisohiso.tests.\(UUID().uuidString).lock")
    }
}
