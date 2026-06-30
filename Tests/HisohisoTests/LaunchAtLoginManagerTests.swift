import Foundation
@testable import Hisohiso
import XCTest

final class LaunchAtLoginManagerTests: XCTestCase {
    func testLaunchAgentPlistURLMatchesBundleIdentifier() {
        let url = LaunchAtLoginManager.launchAgentPlistURL
        XCTAssertEqual(url.lastPathComponent, "\(LaunchAtLoginManager.bundleIdentifier).plist")
        XCTAssertTrue(url.path.contains("Library/LaunchAgents"))
    }

    func testLaunchAgentInstalledReflectsPlistPresence() {
        let exists = FileManager.default.fileExists(atPath: LaunchAtLoginManager.launchAgentPlistURL.path)
        XCTAssertEqual(LaunchAtLoginManager.launchAgentInstalled, exists)
    }
}
