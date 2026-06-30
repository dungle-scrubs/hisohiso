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

    func testDefaultLockURLIsStableNotTemporary() {
        let url = SingleInstanceLock.defaultLockURL
        XCTAssertEqual(url.lastPathComponent, "instance.lock")
        // Must not live in the per-user temp dir, which macOS purges after a few
        // days of no access and would silently disarm the guard.
        XCTAssertFalse(
            url.path.hasPrefix(FileManager.default.temporaryDirectory.path),
            "Lock file must not live in the auto-purged temporary directory"
        )
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.hisohiso.tests.\(UUID().uuidString).lock")
    }
}
