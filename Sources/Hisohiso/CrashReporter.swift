import Cocoa
import Darwin

// MARK: - Crash Reporter

/// Captures crash signals, uncaught exceptions, and unexpected exits.
///
/// ## How it works
/// 1. **Signal handlers** (SIGABRT, SIGSEGV, etc.) write a breadcrumb
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
    static let archiveStore = CrashArchiveStore.live()

    /// Directory for crash archives.
    static let crashesDir: URL = archiveStore.crashesDirectory

    /// Breadcrumb file written by signal/atexit handlers.
    /// Presence of this file on next launch indicates an unclean exit.
    static let breadcrumbPath: URL = archiveStore.breadcrumbPath

    /// PID file so we can detect if the previous instance's process ended.
    static let pidFilePath: URL = archiveStore.pidFilePath

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

    /// Fatal signals we intercept.
    ///
    /// SIGTERM is intentionally excluded because launchd sends it for expected
    /// lifecycle events (e.g. unload/reload), and treating it as a crash causes
    /// noisy false-positive "recovered from a crash" notifications.
    private static let signals: [Int32] = [
        SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP,
    ]

    /// One precomputed "SIGNAL: <name>" prefix, built once at install time.
    ///
    /// `bytes` points at a heap buffer allocated in `precomputeSignalMessages()`
    /// and never freed (it lives for the whole process, like `breadcrumbFD`).
    /// The struct holds only trivial (pointer/integer) members, so the signal
    /// handler can copy it with a plain load — no retain/release, no allocator.
    private struct SignalNameEntry {
        let signal: Int32
        let bytes: UnsafeRawPointer
        let count: Int
    }

    /// Table of precomputed per-signal prefixes, populated in `install()`.
    ///
    /// Intentionally nonisolated: written once during install on the main
    /// thread, then only read from the signal handler, which cannot use actors
    /// or async. The pointed-to bytes are immutable after install.
    private nonisolated(unsafe) static var signalTableBase: UnsafeMutablePointer<SignalNameEntry>?

    /// Number of valid entries in `signalTableBase`.
    ///
    /// Intentionally nonisolated for the same single-writer reason as
    /// `signalTableBase`.
    private nonisolated(unsafe) static var signalTableCount = 0

    /// Fallback prefix bytes used when a signal is not found in the table
    /// (defensive only; handlers are installed just for the known `signals`).
    ///
    /// Intentionally nonisolated: install-time write, signal-handler read.
    private nonisolated(unsafe) static var unknownPrefixPtr: UnsafeRawPointer?

    /// Length of `unknownPrefixPtr`.
    ///
    /// Intentionally nonisolated for the same single-writer reason.
    private nonisolated(unsafe) static var unknownPrefixCount = 0

    // MARK: - Install

    /// Install all crash detection hooks. Call early in `applicationDidFinishLaunching`.
    ///
    /// **Order matters**: `checkPreviousCrash()` must run between `install()` and
    /// any code that could crash, but `openBreadcrumbFD()` creates/truncates the
    /// breadcrumb file. So we defer FD creation until `openBreadcrumbForWriting()`
    /// is called explicitly after the check.
    static func install() {
        writePIDFile()
        installSignalHandlers()
        installExceptionHandler()
        installAtExit()
        logInfo("CrashReporter installed (PID \(ProcessInfo.processInfo.processIdentifier))")
    }

    /// Open the breadcrumb file for writing. Call AFTER `checkPreviousCrash()`.
    ///
    /// This creates/truncates the breadcrumb file so signal handlers can write
    /// to it. Must be called after the previous-crash check, otherwise the check
    /// will always find a (possibly empty) file and false-positive.
    static func openBreadcrumbForWriting() {
        openBreadcrumbFD()
    }

    /// Mark the shutdown as clean. Call from `applicationWillTerminate`.
    static func markCleanShutdown() {
        cleanShutdown = true
        // Remove breadcrumb preemptively so atexit doesn't re-trigger
        archiveStore.markCleanShutdown()
    }

    // MARK: - Previous Crash Detection

    /// Check for a crash breadcrumb from a previous run.
    /// Archives the crash data if found.
    ///
    /// Only treats the breadcrumb as a real crash when the file exists AND has
    /// non-empty content. An empty file (e.g., left by `openBreadcrumbFD`'s
    /// `O_CREAT | O_TRUNC`) is cleaned up silently.
    ///
    /// - Returns: Path to the crash archive, or `nil` if no crash detected.
    @discardableResult
    static func checkPreviousCrash() -> URL? {
        let archivePath = archiveStore.checkPreviousCrash()

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
        precomputeSignalMessages()
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

    /// Precompute the per-signal breadcrumb prefixes ("SIGNAL: <name>").
    ///
    /// Runs during `install()` on a normal thread, where allocation and the
    /// Swift runtime are safe. Each prefix is copied into a heap buffer that is
    /// allocated here once and never freed (process-lifetime, like the
    /// breadcrumb fd). After this returns, the signal handler only reads these
    /// bytes, so it never has to touch the allocator or the string machinery.
    private static func precomputeSignalMessages() {
        guard signalTableBase == nil else { return }

        let count = signals.count
        let table = UnsafeMutablePointer<SignalNameEntry>.allocate(capacity: count)
        for (index, sig) in signals.enumerated() {
            let prefix = allocateBytes("SIGNAL: " + signalName(sig))
            table[index] = SignalNameEntry(signal: sig, bytes: prefix.ptr, count: prefix.count)
        }
        signalTableBase = table
        signalTableCount = count

        let unknown = allocateBytes("SIGNAL: UNKNOWN")
        unknownPrefixPtr = unknown.ptr
        unknownPrefixCount = unknown.count
    }

    /// Copy a string's UTF-8 into a freshly allocated, never-freed heap buffer.
    /// Install-time only; must not be called from a signal handler.
    private static func allocateBytes(_ string: String) -> (ptr: UnsafeRawPointer, count: Int) {
        let utf8 = Array(string.utf8)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(utf8.count, 1), alignment: 1)
        utf8.withUnsafeBytes { src in
            if let base = src.baseAddress, !src.isEmpty {
                buffer.copyMemory(from: base, byteCount: src.count)
            }
        }
        return (UnsafeRawPointer(buffer), utf8.count)
    }

    /// POSIX signal handler. Strictly async-signal-safe: it never calls malloc,
    /// the Swift runtime, or ObjC. It reads the prefix bytes precomputed in
    /// `precomputeSignalMessages()`, assembles the breadcrumb line in a
    /// fixed-size stack buffer (hand-rolling the signal number into ASCII), and
    /// calls only `Darwin.write` / `fsync` on the pre-opened breadcrumb fd.
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        // Locate this signal's precomputed "SIGNAL: <name>" prefix. The table is
        // built once in install() and lives for the whole process, so this is a
        // plain pointer walk: no allocation, no Swift runtime, no ObjC.
        var prefixPtr = unknownPrefixPtr
        var prefixCount = unknownPrefixCount
        if let base = signalTableBase {
            var i = 0
            while i < signalTableCount {
                if base[i].signal == sig {
                    prefixPtr = base[i].bytes
                    prefixCount = base[i].count
                    break
                }
                i += 1
            }
        }

        let fd = breadcrumbFD

        // Assemble the breadcrumb line in a fixed-size stack buffer. For a small
        // constant byte count this lowers to Builtin.stackAlloc (no malloc), and
        // the body performs only pointer stores and integer arithmetic, so it is
        // strictly async-signal-safe. 48 bytes covers "SIGNAL: <name> (<n>)\n".
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 48) { buf in
            guard let dst = buf.baseAddress else { return }
            let cap = buf.count
            var off = 0

            // Precomputed "SIGNAL: <name>" prefix bytes.
            if let prefixPtr {
                let src = prefixPtr.assumingMemoryBound(to: UInt8.self)
                var j = 0
                while j < prefixCount, off < cap {
                    dst[off] = src[j]
                    off += 1
                    j += 1
                }
            }

            // " ("
            if off < cap { dst[off] = 0x20; off += 1 } // space
            if off < cap { dst[off] = 0x28; off += 1 } // (

            // Signal number as decimal ASCII, hand-rolled (least-significant
            // digit first, then reversed in place).
            let numStart = off
            var value = sig < 0 ? UInt32(0) : UInt32(sig)
            repeat {
                guard off < cap else { break }
                dst[off] = 0x30 &+ UInt8(value % 10)
                off += 1
                value /= 10
            } while value != 0
            var lo = numStart
            var hi = off - 1
            while lo < hi {
                let tmp = dst[lo]
                dst[lo] = dst[hi]
                dst[hi] = tmp
                lo += 1
                hi -= 1
            }

            // ")\n"
            if off < cap { dst[off] = 0x29; off += 1 } // )
            if off < cap { dst[off] = 0x0A; off += 1 } // newline

            // Write to breadcrumb fd (async-signal-safe).
            if fd >= 0 {
                _ = Darwin.write(fd, dst, off)
                fsync(fd)
            }
        }

        // Re-raise with default handler so the OS generates a crash report too.
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Map signal number to name. Called only at install time while
    /// precomputing breadcrumb prefixes, never from a signal handler.
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
