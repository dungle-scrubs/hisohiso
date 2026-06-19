import Foundation

/// Publishes recording state and audio levels to an optional external waveform
/// display over a local Unix socket.
///
/// The display listens at `/tmp/hisohiso-waveform.sock` and accepts newline-
/// delimited commands:
/// - `state idle|recording|transcribing|error` — recording state changes
/// - `levels 50,60,70,80,70,60,50` — audio waveform levels (7 bars, 0–100)
///
/// When nothing is listening, sends are no-ops and Hisohiso's own floating pill
/// acts as the fallback indicator.
///
/// ## Connection strategy
/// Uses a persistent socket connection to avoid per-message connect/close overhead
/// (audio levels arrive at 20Hz during recording). The connection is lazily opened
/// on the first send and kept alive. When the connection is re-established, the
/// latest state is replayed before fresh level updates so the display does not stay
/// stuck in idle after startup or restart races.
///
/// ## Thread safety
/// All socket I/O happens on the serial `queue`.
final class WaveformBridge: @unchecked Sendable {
    static let shared = WaveformBridge()

    private let queue = DispatchQueue(label: "com.hisohiso.waveform", qos: .utility)

    /// Queue-confined connection state and retry metadata.
    private var connection = WaveformConnectionStore()

    /// Thread-safe check for external display availability.
    var isAvailable: Bool {
        queue.sync { connection.isAvailable }
    }

    /// Unix socket path for the external waveform display.
    private let socketPath = "/tmp/hisohiso-waveform.sock"

    private init() {
        checkAvailability()
    }

    // MARK: - Public API

    /// Send the current recording state to the external waveform display.
    /// - Parameter state: The recording state.
    func sendState(_ state: RecordingState) {
        let command = switch state {
        case .idle:
            "state idle"
        case .recording:
            "state recording"
        case .transcribing:
            "state transcribing"
        case .error:
            "state error"
        }

        queue.async { [weak self] in
            guard let self else { return }
            connection.recordStateCommand(command)
            sendQueuedCommand(command)
        }
    }

    /// Send audio levels to the external waveform display.
    /// - Parameter levels: Array of 7 normalized levels (0–100).
    func sendLevels(_ levels: [UInt8]) {
        let csv = levels.map(String.init).joined(separator: ",")
        queue.async { [weak self] in
            self?.sendQueuedCommand("levels \(csv)")
        }
    }

    /// Check whether the external waveform display socket currently exists.
    func checkAvailability() {
        queue.async { [weak self] in
            guard let self else { return }
            connection.markAvailable(FileManager.default.fileExists(atPath: socketPath))
        }
    }

    // MARK: - Private

    private enum ConnectionStatus {
        case existing
        case reconnected
        case unavailable
    }

    /// Ensure a persistent connection is open.
    /// Must be called on `queue`.
    private func ensureConnected() -> ConnectionStatus {
        if connection.isConnected {
            return .existing
        }

        guard FileManager.default.fileExists(atPath: socketPath) else {
            connection.markAvailable(false)
            return .unavailable
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            logDebug("Waveform: failed to create socket")
            return .unavailable
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return .unavailable
        }
        pathBytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                dest.update(from: src.baseAddress!, count: src.count)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            logDebug("Waveform: failed to connect to display bridge")
            connection.markAvailable(false)
            return .unavailable
        }

        connection.connect(fd: fd)
        logInfo("Waveform: connected to external display bridge")
        return .reconnected
    }

    /// Close the persistent connection.
    /// Must be called on `queue`.
    private func disconnect() {
        if let fd = connection.disconnect() {
            close(fd)
        }
    }

    /// Write one newline-delimited command to the active socket.
    /// Must be called on `queue` with an open connection.
    private func writeCommand(_ command: String) -> Bool {
        let message = command + "\n"
        let written = message.withCString { ptr -> Int in
            Darwin.write(connection.socketFD, ptr, strlen(ptr))
        }
        return written >= 0
    }

    /// Send a command over the persistent connection.
    /// Reconnects automatically on failure and replays the latest state first.
    private func sendQueuedCommand(_ command: String) {
        let status = ensureConnected()
        if case .unavailable = status {
            return
        }

        if case .reconnected = status,
           command != connection.latestStateCommand,
           !writeCommand(connection.latestStateCommand)
        {
            logDebug("Waveform: failed to replay state after reconnect")
            disconnect()
            return
        }

        if writeCommand(command) {
            return
        }

        logDebug("Waveform: write failed, reconnecting")
        disconnect()
        if case .unavailable = ensureConnected() {
            return
        }

        if command != connection.latestStateCommand,
           !writeCommand(connection.latestStateCommand)
        {
            logDebug("Waveform: failed to replay state after reconnect retry")
            disconnect()
            return
        }

        if !writeCommand(command) {
            logDebug("Waveform: retry write failed, disconnecting")
            disconnect()
        }
    }
}
