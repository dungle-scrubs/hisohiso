import Foundation

/// Stores and recovers crash breadcrumbs and crash archive files.
///
/// This type owns file-system behavior for previous-crash detection so the
/// signal-handling code can stay small and untested crash recovery logic can be
/// verified with injectable paths. It is unchecked sendable because its stored
/// dependencies are immutable and operations do not mutate instance state.
struct CrashArchiveStore: @unchecked Sendable {
    let crashesDirectory: URL
    let breadcrumbPath: URL
    let pidFilePath: URL
    let logsDirectory: URL

    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    /// Create a crash archive store.
    /// - Parameters:
    ///   - crashesDirectory: Directory where timestamped archives are written.
    ///   - breadcrumbPath: File written by crash and dirty-exit handlers.
    ///   - pidFilePath: File containing the previous process identifier.
    ///   - logsDirectory: Directory containing application logs to copy.
    ///   - fileManager: File manager used for file-system operations.
    ///   - now: Clock used to produce deterministic archive names in tests.
    init(
        crashesDirectory: URL,
        breadcrumbPath: URL,
        pidFilePath: URL,
        logsDirectory: URL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.crashesDirectory = crashesDirectory
        self.breadcrumbPath = breadcrumbPath
        self.pidFilePath = pidFilePath
        self.logsDirectory = logsDirectory
        self.fileManager = fileManager
        self.now = now
    }

    /// Default store under `~/Library/Logs/Hisohiso`.
    /// - Returns: Store configured for the current user account.
    static func live() -> CrashArchiveStore {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hisohiso")

        return CrashArchiveStore(
            crashesDirectory: logsDirectory.appendingPathComponent("crashes"),
            breadcrumbPath: logsDirectory.appendingPathComponent(".crash-breadcrumb"),
            pidFilePath: logsDirectory.appendingPathComponent(".hisohiso.pid"),
            logsDirectory: logsDirectory
        )
    }

    /// Check for a previous crash breadcrumb and archive it when valid.
    /// - Returns: Archive directory URL, or `nil` when no crash is detected.
    func checkPreviousCrash() -> URL? {
        guard fileManager.fileExists(atPath: breadcrumbPath.path) else {
            return nil
        }

        let raw = (try? String(contentsOf: breadcrumbPath, encoding: .utf8)) ?? ""
        let breadcrumb = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        defer { removePreviousRunFiles() }

        guard !breadcrumb.isEmpty else {
            return nil
        }

        guard !breadcrumb.hasPrefix("SIGNAL: SIGTERM") else {
            logInfo("Ignoring expected SIGTERM termination breadcrumb")
            return nil
        }

        logWarning("Previous crash detected: \(breadcrumb)")
        return archiveCrash(breadcrumb: breadcrumb)
    }

    /// Remove previous-run breadcrumb and PID files during clean shutdown.
    func markCleanShutdown() {
        removePreviousRunFiles()
    }

    /// Archive the crash breadcrumb and recent logs into a timestamped directory.
    /// - Parameter breadcrumb: Content of the breadcrumb file.
    /// - Returns: Path to the archive directory, or `nil` when archiving fails.
    func archiveCrash(breadcrumb: String) -> URL? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now())
            .replacingOccurrences(of: ":", with: "-")

        let archiveDirectory = crashesDirectory.appendingPathComponent("crash-\(timestamp)")

        do {
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            try breadcrumb.write(
                to: archiveDirectory.appendingPathComponent("breadcrumb.txt"),
                atomically: true,
                encoding: .utf8
            )
            try buildSystemInfo().write(
                to: archiveDirectory.appendingPathComponent("system-info.txt"),
                atomically: true,
                encoding: .utf8
            )
            copyRecentLogs(to: archiveDirectory)
            return archiveDirectory
        } catch {
            logError("Failed to archive crash: \(error)")
            return nil
        }
    }

    /// Build system metadata for the crash archive.
    /// - Returns: Human-readable system metadata.
    private func buildSystemInfo() -> String {
        let process = ProcessInfo.processInfo
        var lines: [String] = []
        lines.append("Hisohiso Crash Report")
        lines.append("=====================")
        lines.append("Date: \(ISO8601DateFormatter().string(from: now()))")
        lines.append("OS: \(process.operatingSystemVersionString)")
        lines.append("Process: \(process.processName) (PID from file)")
        lines.append("Physical Memory: \(process.physicalMemory / (1024 * 1024)) MB")
        lines.append("Active Processors: \(process.activeProcessorCount)")
        lines.append("Uptime: \(Int(process.systemUptime)) seconds")

        if let pid = try? String(contentsOf: pidFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            lines.append("Previous PID: \(pid)")
        }

        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? Int64
        {
            lines.append("Free Disk: \(freeBytes / (1024 * 1024 * 1024)) GB")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Copy recent log files into a crash archive.
    /// - Parameter archiveDirectory: Archive directory receiving copied logs.
    private func copyRecentLogs(to archiveDirectory: URL) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )
        .filter({ $0.lastPathComponent.hasPrefix("hisohiso-") && $0.pathExtension == "log" })
        .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        else { return }

        for file in files.prefix(2) {
            let destination = archiveDirectory.appendingPathComponent(file.lastPathComponent)
            try? fileManager.copyItem(at: file, to: destination)
        }
    }

    /// Remove previous-run marker files.
    private func removePreviousRunFiles() {
        try? fileManager.removeItem(at: breadcrumbPath)
        try? fileManager.removeItem(at: pidFilePath)
    }
}
