import Foundation
import OSLog

// MARK: - Log Level

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

// MARK: - Logger

/// File + OSLog logger.
///
/// ## Thread safety
/// All mutable state (`fileHandle`) is accessed exclusively on `queue`.
/// The `ISO8601DateFormatter` used for timestamps is thread-safe (unlike `DateFormatter`).
/// Free functions (`logInfo`, `logError`, …) may be called from any thread.
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.hisohiso.app", category: "general")
    private let fileHandle: FileHandle?
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.hisohiso.logger", qos: .utility)

    /// Maximum age (in days) for log files before automatic cleanup.
    private let maxLogAgeDays = AppConstants.maxLogAgeDays

    private init() {
        // Create log directory
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hisohiso")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create/open log file (rotates daily)
        let dateStr = ISO8601DateFormatter().string(from: Date())
            .prefix(10)
            .replacingOccurrences(of: "-", with: "")
        logFileURL = logsDir.appendingPathComponent("hisohiso-\(dateStr).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Prune old log files on startup
        pruneOldLogs(in: logsDir)
    }

    deinit {
        try? fileHandle?.close()
    }

    /// Log a message with the specified level.
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Log level (debug, info, warning, error)
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        // Write to OSLog (thread-safe by design)
        os_log("%{public}@", log: osLog, type: level.osLogType, message)

        // Build the log line and write to file on the serial queue.
        // ISO8601DateFormatter is thread-safe, but we do all formatting on
        // the queue to avoid any contention and keep writes ordered.
        queue.async { [weak self] in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"

            if let data = logLine.data(using: .utf8) {
                self?.fileHandle?.write(data)
                try? self?.fileHandle?.synchronize()
            }
        }
    }

    /// Path to the current log file (for tail -f)
    var logFilePath: String { logFileURL.path }

    /// Path to the logs directory.
    var logsDirectory: URL {
        logFileURL.deletingLastPathComponent()
    }

    /// Write a log line **synchronously** on the calling thread.
    ///
    /// Only use this from crash/exit handlers where the dispatch queue may
    /// never execute. This bypasses the serial queue and writes directly.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Log level
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    func logSync(
        _ message: String,
        level: LogLevel = .error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        // Write to OSLog first (always safe)
        os_log("%{public}@", log: osLog, type: level.osLogType, message)

        // Synchronous file write — no dispatch queue
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"

        if let data = logLine.data(using: .utf8) {
            // Use the queue synchronously to avoid racing with async writes
            queue.sync {
                fileHandle?.write(data)
                try? fileHandle?.synchronize()
            }
        }
    }

    // MARK: - Log Rotation

    /// Remove log files older than `maxLogAgeDays`.
    private func pruneOldLogs(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -maxLogAgeDays, to: Date()) ?? Date()

        for file in files where file.lastPathComponent.hasPrefix("hisohiso-") && file.pathExtension == "log" {
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let creationDate = attrs[.creationDate] as? Date,
                  creationDate < cutoff
            else { continue }

            try? fm.removeItem(at: file)
        }
    }
}

// MARK: - Convenience Functions

func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .debug, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .info, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .warning, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .error, file: file, function: function, line: line)
}
