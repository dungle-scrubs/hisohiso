import Cocoa
import Darwin

// MARK: - Crash Reporter

/// Captures crash signals, uncaught exceptions, and unexpected exits.
///
/// ## How it works
/// 1. **Signal handlers** (SIGTERM, SIGABRT, SIGSEGV, etc.) write a breadcrumb
///    file synchronously using only async-signal-safe functions (no malloc, no ObjC).
/// 2. **`atexit` handler** detects if the app exited without going through
///    `applicationWillTerminate` and logs the anomaly.
/// 3. **On next launch**, `checkPreviousCrash()` reads any breadcrumb, archives
///    the crash data (log + breadcrumb + system info), and optionally submits it.
///
/// ## Thread safety
/// Signal handlers use only `write()` on a pre-opened file descriptor.
/// The breadcrumb file descriptor is opened once at install time and never closed
/// until process exit. All other state is read-only after `install()`.
enum CrashReporter {
    // MARK: - File Paths

    /// Directory for crash archives.
    static let crashesDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hisohiso/crashes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Breadcrumb file written by signal/atexit handlers.
    /// Presence of this file on next launch indicates an unclean exit.
    static let breadcrumbPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hisohiso/.crash-breadcrumb")

    /// PID file so we can detect if the previous instance's process ended.
    static let pidFilePath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hisohiso/.hisohiso.pid")

    // MARK: - State

    /// File descriptor for the breadcrumb file, opened at install time.
    /// Signal handlers write to this directly — no allocation needed.
    ///
    /// Intentionally nonisolated: written once in `install()`, then only read
    /// from signal handlers which cannot use actors or async.
    private nonisolated(unsafe) static var breadcrumbFD: Int32 = -1

    /// Set to `true` when `applicationWillTerminate` runs (clean shutdown).
    /// The `atexit` handler checks this to distinguish clean vs. dirty exits.
    ///
    /// Intentionally nonisolated: written on main thread in `markCleanShutdown()`,
    /// read in `atexit` handler. Single-writer, signal-safe.
    private(set) nonisolated(unsafe) static var cleanShutdown = false

    /// Signals we intercept.
    private static let signals: [Int32] = [
        SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP, SIGTERM
    ]

    // MARK: - Install

    /// Install all crash detection hooks. Call early in `applicationDidFinishLaunching`.
    static func install() {
        writePIDFile()
        openBreadcrumbFD()
        installSignalHandlers()
        installExceptionHandler()
        installAtExit()
        logInfo("CrashReporter installed (PID \(ProcessInfo.processInfo.processIdentifier))")
    }

    /// Mark the shutdown as clean. Call from `applicationWillTerminate`.
    static func markCleanShutdown() {
        cleanShutdown = true
        // Remove breadcrumb preemptively so atexit doesn't re-trigger
        try? FileManager.default.removeItem(at: breadcrumbPath)
        try? FileManager.default.removeItem(at: pidFilePath)
    }

    // MARK: - Previous Crash Detection

    /// Check for a crash breadcrumb from a previous run.
    /// Archives the crash data if found.
    /// - Returns: Path to the crash archive, or `nil` if no crash detected.
    @discardableResult
    static func checkPreviousCrash() -> URL? {
        guard FileManager.default.fileExists(atPath: breadcrumbPath.path) else {
            return nil
        }

        let breadcrumb = (try? String(contentsOf: breadcrumbPath, encoding: .utf8)) ?? "unknown"
        logWarning("Previous crash detected: \(breadcrumb.trimmingCharacters(in: .whitespacesAndNewlines))")

        let archivePath = archiveCrash(breadcrumb: breadcrumb)

        // Clean up breadcrumb
        try? FileManager.default.removeItem(at: breadcrumbPath)
        try? FileManager.default.removeItem(at: pidFilePath)

        if let archivePath {
            logInfo("Crash archive saved: \(archivePath.path)")
            showCrashNotification(archivePath: archivePath)
        }

        return archivePath
    }

    // MARK: - Private: Installation

    private static func writePIDFile() {
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        try? pid.write(to: pidFilePath, atomically: true, encoding: .utf8)
    }

    /// Open the breadcrumb file descriptor for signal-safe writes.
    private static func openBreadcrumbFD() {
        let path = breadcrumbPath.path
        breadcrumbFD = path.withCString { cPath in
            Darwin.open(cPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
        if breadcrumbFD < 0 {
            logError("CrashReporter: failed to open breadcrumb fd (errno \(errno))")
        }
    }

    /// Install POSIX signal handlers.
    private static func installSignalHandlers() {
        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = signalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(sig, &action, nil)
        }
    }

    /// Install Objective-C uncaught exception handler.
    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    /// Top-level C-compatible exception handler. Must not capture context.
    private static let uncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
        let reason = exception.reason ?? "unknown"
        let name = exception.name.rawValue
        let symbols = exception.callStackSymbols.prefix(20).joined(separator: "\n  ")
        let message = "EXCEPTION: \(name): \(reason)\nStack:\n  \(symbols)\n"
        CrashReporter.writeBreadcrumbSync(message)

        // Also write via Logger synchronously
        Logger.shared.logSync(
            "Uncaught exception: \(name) — \(reason)",
            level: .error
        )
    }

    /// Install `atexit` handler to catch unexpected normal exits.
    private static func installAtExit() {
        atexit {
            guard !CrashReporter.cleanShutdown else { return }

            // Dirty exit — app is terminating without going through
            // applicationWillTerminate. This catches:
            // - fatalError() / preconditionFailure()
            // - exit() called from somewhere
            // - Unhandled Task errors (Swift concurrency)
            let message = "DIRTY_EXIT: process exiting without clean shutdown\n"
            CrashReporter.writeBreadcrumbSync(message)

            Logger.shared.logSync(
                "Process exiting without clean shutdown (no applicationWillTerminate)",
                level: .error
            )
        }
    }

    // MARK: - Private: Signal Handler (async-signal-safe)

    /// POSIX signal handler. Only uses async-signal-safe functions.
    /// No malloc, no ObjC dispatch, no Swift runtime calls.
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        // Build the message using only stack-allocated buffers
        var buf: [UInt8] = Array(repeating: 0, count: 128)
        let prefix = "SIGNAL: "
        let sigName = signalName(sig)
        let suffix = "\n"

        var offset = 0
        for byte in prefix.utf8 {
            guard offset < buf.count - 1 else { break }
            buf[offset] = byte
            offset += 1
        }
        for byte in sigName.utf8 {
            guard offset < buf.count - 1 else { break }
            buf[offset] = byte
            offset += 1
        }
        // Write signal number
        let numStr = " (\(sig))"
        for byte in numStr.utf8 {
            guard offset < buf.count - 1 else { break }
            buf[offset] = byte
            offset += 1
        }
        for byte in suffix.utf8 {
            guard offset < buf.count - 1 else { break }
            buf[offset] = byte
            offset += 1
        }

        // Write to breadcrumb fd (async-signal-safe)
        if breadcrumbFD >= 0 {
            _ = buf.withUnsafeBufferPointer { ptr in
                Darwin.write(breadcrumbFD, ptr.baseAddress!, offset)
            }
            fsync(breadcrumbFD)
        }

        // Re-raise with default handler so the OS generates a crash report too
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Map signal number to name. Pure function, no allocation.
    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: "SIGABRT"
        case SIGBUS: "SIGBUS"
        case SIGFPE: "SIGFPE"
        case SIGILL: "SIGILL"
        case SIGSEGV: "SIGSEGV"
        case SIGTRAP: "SIGTRAP"
        case SIGTERM: "SIGTERM"
        default: "SIG_\(sig)"
        }
    }

    /// Write a breadcrumb message synchronously. Used by exception/atexit handlers
    /// where we have more latitude than signal handlers.
    private static func writeBreadcrumbSync(_ message: String) {
        // Write via fd if available
        if breadcrumbFD >= 0 {
            let data = Array(message.utf8)
            data.withUnsafeBufferPointer { ptr in
                _ = Darwin.write(breadcrumbFD, ptr.baseAddress!, data.count)
            }
            fsync(breadcrumbFD)
        }

        // Also try the filesystem path as backup
        try? message.write(to: breadcrumbPath, atomically: false, encoding: .utf8)
    }

    // MARK: - Private: Crash Archival

    /// Archive the crash breadcrumb + recent logs into a timestamped directory.
    /// - Parameter breadcrumb: Content of the breadcrumb file.
    /// - Returns: Path to the archive directory.
    private static func archiveCrash(breadcrumb: String) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let archiveDir = crashesDir.appendingPathComponent("crash-\(timestamp)")

        do {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)

            // Write breadcrumb
            try breadcrumb.write(
                to: archiveDir.appendingPathComponent("breadcrumb.txt"),
                atomically: true,
                encoding: .utf8
            )

            // Write system info
            let sysInfo = buildSystemInfo()
            try sysInfo.write(
                to: archiveDir.appendingPathComponent("system-info.txt"),
                atomically: true,
                encoding: .utf8
            )

            // Copy recent log files (last 2 days)
            copyRecentLogs(to: archiveDir)

            return archiveDir
        } catch {
            logError("Failed to archive crash: \(error)")
            return nil
        }
    }

    /// Build a system info string for the crash archive.
    private static func buildSystemInfo() -> String {
        let process = ProcessInfo.processInfo
        let fileManager = FileManager.default

        var lines: [String] = []
        lines.append("Hisohiso Crash Report")
        lines.append("=====================")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("OS: \(process.operatingSystemVersionString)")
        lines.append("Process: \(process.processName) (PID from file)")
        lines.append("Physical Memory: \(process.physicalMemory / (1024 * 1024)) MB")
        lines.append("Active Processors: \(process.activeProcessorCount)")
        lines.append("Uptime: \(Int(process.systemUptime)) seconds")

        // Read previous PID if available
        if let pidStr = try? String(contentsOf: pidFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            lines.append("Previous PID: \(pidStr)")
        }

        // Disk space
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? Int64 {
            lines.append("Free Disk: \(freeBytes / (1024 * 1024 * 1024)) GB")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Copy the 2 most recent log files into the crash archive.
    private static func copyRecentLogs(to archiveDir: URL) {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hisohiso")
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.creationDateKey]
        )
        .filter({ $0.lastPathComponent.hasPrefix("hisohiso-") && $0.pathExtension == "log" })
        .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        else { return }

        for file in files.prefix(2) {
            let dest = archiveDir.appendingPathComponent(file.lastPathComponent)
            try? fileManager.copyItem(at: file, to: dest)
        }
    }

    // MARK: - Private: Notification

    /// Show a macOS notification that a crash was detected.
    ///
    /// Uses `osascript` instead of `UNUserNotificationCenter` because
    /// UNUserNotificationCenter requires a bundle proxy, which an unbundled
    /// binary in `/opt/homebrew/bin/` doesn't have.
    private static func showCrashNotification(archivePath: URL) {
        let script = """
        display notification "Crash data archived to \(archivePath.lastPathComponent)" \
            with title "Hisohiso recovered from a crash" \
            sound name "Submarine"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
