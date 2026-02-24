import Accelerate
import Foundation

/// Bridge to communicate with the custom Sinew hisohiso module via Unix socket IPC.
///
/// The custom module listens on `/tmp/hisohiso-sinew.sock` and accepts:
/// - `state idle|recording|transcribing|error` — recording state changes
/// - `levels 50,60,70,80,70,60,50` — audio waveform levels (7 bars, 0–100)
///
/// ## Connection strategy
/// Uses a persistent socket connection to avoid per-message connect/close overhead
/// (audio levels arrive at 20Hz during recording). The connection is lazily opened
/// on the first send and kept alive. If a write fails, the connection is dropped
/// and re-established on the next send.
///
/// ## Thread safety
/// All socket I/O happens on the serial `queue`. UserDefaults-backed properties
/// are atomic for simple types.
final class SinewBridge: @unchecked Sendable {
    static let shared = SinewBridge()

    private let queue = DispatchQueue(label: "com.hisohiso.sinew", qos: .utility)

    /// Persistent socket file descriptor, or -1 if disconnected.
    /// Only accessed on `queue`.
    private var socketFD: Int32 = -1

    /// Whether the hisohiso Sinew module socket file exists.
    /// Only written on `queue`.
    private var _isAvailable = false

    /// Thread-safe check for Sinew hisohiso module availability.
    var isAvailable: Bool {
        queue.sync { _isAvailable }
    }

    /// Unix socket path for the custom hisohiso Sinew module.
    private let socketPath = "/tmp/hisohiso-sinew.sock"

    /// Whether to use Sinew for visualization.
    var useSinewVisualization: Bool {
        get { UserDefaults.standard.hasValue(for: .useSinewVisualization) ? UserDefaults.standard.bool(for: .useSinewVisualization) : true }
        set { UserDefaults.standard.set(newValue, for: .useSinewVisualization) }
    }

    /// Whether to show the floating pill.
    var showFloatingPill: Bool {
        get { UserDefaults.standard.bool(for: .showFloatingPill) }
        set { UserDefaults.standard.set(newValue, for: .showFloatingPill) }
    }

    /// Show the floating pill only if the user explicitly enabled it,
    /// OR if the Sinew hisohiso module is not available (fallback).
    var shouldShowFloatingPill: Bool {
        showFloatingPill || !isAvailable
    }

    /// Should we send state updates to Sinew?
    var shouldUseSinew: Bool {
        isAvailable && useSinewVisualization
    }

    private init() {
        if !UserDefaults.standard.hasValue(for: .showFloatingPill) {
            UserDefaults.standard.set(false, for: .showFloatingPill)
        }
        checkAvailability()
    }

    // MARK: - Public API

    /// Send current recording state to the Sinew hisohiso module.
    /// - Parameter state: The recording state.
    func sendState(_ state: RecordingState) {
        guard useSinewVisualization else { return }

        let command: String
        switch state {
        case .idle:
            command = "state idle"
        case .recording:
            command = "state recording"
        case .transcribing:
            command = "state transcribing"
        case .error:
            command = "state error"
        }
        send(command)
    }

    /// Send audio levels to the Sinew hisohiso module for waveform visualization.
    /// - Parameter levels: Array of 7 normalized levels (0–100).
    func sendLevels(_ levels: [UInt8]) {
        guard useSinewVisualization else { return }
        let csv = levels.map(String.init).joined(separator: ",")
        send("levels \(csv)")
    }

    /// Check if the hisohiso Sinew module socket file exists.
    func checkAvailability() {
        queue.async { [weak self] in
            guard let self else { return }
            self._isAvailable = FileManager.default.fileExists(atPath: self.socketPath)

            if self._isAvailable {
                logDebug("Sinew hisohiso socket available at \(self.socketPath)")
            }
        }
    }

    // MARK: - Private

    /// Ensure a persistent connection is open. Returns true if connected.
    /// Must be called on `queue`.
    private func ensureConnected() -> Bool {
        if socketFD >= 0 {
            return true
        }

        // Check socket file exists
        guard FileManager.default.fileExists(atPath: socketPath) else {
            _isAvailable = false
            return false
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            logDebug("Sinew: Failed to create socket")
            return false
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return false
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
            logDebug("Sinew: Failed to connect to hisohiso module")
            _isAvailable = false
            return false
        }

        socketFD = fd
        _isAvailable = true
        logInfo("Sinew: Connected to hisohiso module")
        return true
    }

    /// Close the persistent connection.
    /// Must be called on `queue`.
    private func disconnect() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    /// Send a command over the persistent connection.
    /// Reconnects automatically on failure.
    private func send(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.ensureConnected() else { return }

            let message = command + "\n"
            let written = message.withCString { ptr -> Int in
                Darwin.write(self.socketFD, ptr, strlen(ptr))
            }

            if written < 0 {
                // Connection broken — drop and retry next time
                logDebug("Sinew: Write failed, disconnecting")
                self.disconnect()
            }
        }
    }
}

// MARK: - Audio Level Calculator

extension SinewBridge {
    /// Calculate waveform levels from audio samples using Accelerate.
    /// - Parameter samples: Raw audio samples (16kHz mono).
    /// - Returns: Array of 7 normalized levels (0–100).
    static func calculateAudioLevels(from samples: [Float]) -> [UInt8] {
        let numBars = AppConstants.waveformBarCount
        guard !samples.isEmpty else {
            return [UInt8](repeating: 0, count: numBars)
        }

        let chunkSize = max(1, samples.count / numBars)
        var levels = [UInt8]()
        levels.reserveCapacity(numBars)

        for i in 0 ..< numBars {
            let start = i * chunkSize
            guard start < samples.count else {
                levels.append(0)
                continue
            }

            let end = min(start + chunkSize, samples.count)
            let count = end - start

            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + start, 1, &rms, vDSP_Length(count))
            }

            // Sqrt compression: boosts quiet speech, prevents loud sounds from clipping
            let linear = rms * AppConstants.audioLevelMultiplier
            let compressed = sqrt(linear) * 10.0
            let normalized = min(100, max(0, Int(compressed)))
            levels.append(UInt8(normalized))
        }

        return levels
    }
}
