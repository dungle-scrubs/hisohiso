import Darwin
import Foundation

enum SingleInstanceLockError: Error, LocalizedError, Equatable {
    case alreadyRunning(ownerPID: Int32?)
    case openFailed(errno: Int32)
    case lockFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case let .alreadyRunning(ownerPID):
            if let ownerPID {
                "Another Hisohiso instance is already running (PID \(ownerPID))"
            } else {
                "Another Hisohiso instance is already running"
            }
        case let .openFailed(errno):
            "Failed to open instance lock: \(String(cString: strerror(errno)))"
        case let .lockFailed(errno):
            "Failed to acquire instance lock: \(String(cString: strerror(errno)))"
        }
    }
}

/// Holds an advisory process lock so only one app-mode Hisohiso instance can run.
///
/// macOS can launch the same bundle through multiple mechanisms at once
/// (LaunchAgent, Login Item, manual `open -a`). LaunchServices does not coalesce
/// those when a LaunchAgent starts the executable directly, so the app needs its
/// own guard before installing global event taps.
final class SingleInstanceLock {
    static let defaultLockURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.hisohiso.app.lock")

    private let fd: Int32

    init(lockURL: URL = SingleInstanceLock.defaultLockURL) throws {
        let path = lockURL.path
        let openedFD = path.withCString { cPath in
            Darwin.open(cPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        }

        guard openedFD >= 0 else {
            throw SingleInstanceLockError.openFailed(errno: errno)
        }

        guard flock(openedFD, LOCK_EX | LOCK_NB) == 0 else {
            let lockErrno = errno
            Darwin.close(openedFD)
            if lockErrno == EWOULDBLOCK || lockErrno == EAGAIN {
                throw SingleInstanceLockError.alreadyRunning(ownerPID: Self.ownerPID(at: lockURL))
            }
            throw SingleInstanceLockError.lockFailed(errno: lockErrno)
        }

        fd = openedFD
        writeCurrentPID()
    }

    deinit {
        flock(fd, LOCK_UN)
        Darwin.close(fd)
    }

    private func writeCurrentPID() {
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = ftruncate(fd, 0)
        _ = lseek(fd, 0, SEEK_SET)
        pid.withCString { ptr in
            _ = Darwin.write(fd, ptr, strlen(ptr))
        }
    }

    private static func ownerPID(at lockURL: URL) -> Int32? {
        guard let content = try? String(contentsOf: lockURL, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return pid
    }
}
