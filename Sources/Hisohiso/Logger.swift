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

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.hisohiso.app", category: "general")
    private let fileHandle: FileHandle?
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.hisohiso.logger", qos: .utility)

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

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
    }

    deinit {
        try? fileHandle?.close()
    }

    /// Log a message with the specified level
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
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"

        // Write to OSLog
        os_log("%{public}@", log: osLog, type: level.osLogType, message)

        // Write to file for on-device troubleshooting
        queue.async { [weak self] in
            if let data = logLine.data(using: .utf8) {
                self?.fileHandle?.write(data)
                try? self?.fileHandle?.synchronize()
            }
        }
    }

    /// Path to the current log file (for tail -f)
    var logFilePath: String { logFileURL.path }
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
