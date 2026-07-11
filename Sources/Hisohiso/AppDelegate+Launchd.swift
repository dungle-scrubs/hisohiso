import Cocoa
import Darwin

// MARK: - Single-Instance & launchd Coordination

extension AppDelegate {
    /// Acquire the app-mode singleton guard before installing global monitors.
    /// - Returns: `true` when this process owns the app instance lock.
    func acquireSingleInstanceLock() -> Bool {
        do {
            singleInstanceLock = try SingleInstanceLock()
            return true
        } catch let SingleInstanceLockError.alreadyRunning(ownerPID) {
            if isManagedByLaunchd,
               let ownerPID,
               terminateExistingInstance(pid: ownerPID),
               let lock = try? SingleInstanceLock()
            {
                singleInstanceLock = lock
                return true
            }

            logInfo("Another Hisohiso instance is already running; exiting duplicate launch")
            return false
        } catch {
            logError("Failed to acquire Hisohiso instance lock: \(error.localizedDescription)")
            return false
        }
    }

    /// Prefer the LaunchAgent-owned app process over LaunchServices/manual launches.
    func shouldDeferToLaunchdInstance() -> Bool {
        !isManagedByLaunchd && launchdJobIsLoaded()
    }

    private var isManagedByLaunchd: Bool {
        ProcessInfo.processInfo.environment["HISOHISO_MANAGED"] == "launchd"
    }

    private func launchdJobIsLoaded() -> Bool {
        runLaunchctl(arguments: ["print", launchdJobTarget()]) == 0
    }

    func kickstartLaunchdInstance() {
        _ = runLaunchctl(arguments: ["kickstart", "-k", launchdJobTarget()])
    }

    private func launchdJobTarget() -> String {
        "gui/\(getuid())/com.hisohiso.app"
    }

    private func runLaunchctl(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }

    private func terminateExistingInstance(pid: Int32) -> Bool {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            return false
        }

        guard kill(pid, SIGTERM) == 0 else {
            return false
        }

        for _ in 0..<20 {
            usleep(50000)
            if kill(pid, 0) != 0, errno == ESRCH {
                return true
            }
        }

        return false
    }
}
