import Foundation

struct AppLifecycleCoordinator {
    var installCrashReporter: () -> Void = { CrashReporter.install() }
    var checkPreviousCrash: () -> URL? = { CrashReporter.checkPreviousCrash() }
    var openBreadcrumb: () -> Void = { CrashReporter.openBreadcrumbForWriting() }
    var markCleanShutdown: () -> Void = { CrashReporter.markCleanShutdown() }
    var logSync: (String) -> Void = { Logger.shared.logSync($0, level: .info) }

    func prepareLaunch() -> URL? {
        installCrashReporter()
        logInfo("Hisohiso starting...")
        logInfo("Log file: \(Logger.shared.logFilePath)")
        let archive = checkPreviousCrash()
        if let archive {
            logWarning("Previous session crashed. Archive: \(archive.path)")
        }
        openBreadcrumb()
        return archive
    }

    func finishTermination() {
        markCleanShutdown()
        logSync("Hisohiso shutting down (clean)")
    }
}
