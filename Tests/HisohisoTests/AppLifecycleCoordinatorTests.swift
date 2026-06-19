import XCTest
@testable import Hisohiso

final class AppLifecycleCoordinatorTests: XCTestCase {
    func testPrepareLaunchInstallsCrashReporterBeforeOpeningBreadcrumb() {
        var calls: [String] = []
        let coordinator = AppLifecycleCoordinator(
            installCrashReporter: { calls.append("install") },
            checkPreviousCrash: { calls.append("check"); return nil },
            openBreadcrumb: { calls.append("open") },
            markCleanShutdown: { calls.append("clean") },
            logSync: { _ in calls.append("log") }
        )

        _ = coordinator.prepareLaunch()

        XCTAssertEqual(calls, ["install", "check", "open"])
    }

    func testFinishTerminationMarksCleanShutdownBeforeSyncLog() {
        var calls: [String] = []
        let coordinator = AppLifecycleCoordinator(
            installCrashReporter: { calls.append("install") },
            checkPreviousCrash: { calls.append("check"); return nil },
            openBreadcrumb: { calls.append("open") },
            markCleanShutdown: { calls.append("clean") },
            logSync: { _ in calls.append("log") }
        )

        coordinator.finishTermination()

        XCTAssertEqual(calls, ["clean", "log"])
    }
}
