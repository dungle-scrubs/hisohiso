import Foundation

/// Bridge to communicate with Sinew's external Hisohiso module via Unix socket IPC.
///
/// ## Thread safety
/// All socket I/O and `_isAvailable` writes happen on the serial `queue`.
/// `useSinewVisualization` and `showFloatingPill` are backed by `UserDefaults`
/// (atomic for simple types). Safe to call `sendState` from any thread.
final class SinewBridge: @unchecked Sendable {
    static let shared = SinewBridge()

    private let moduleID = "hisohiso"
    private let queue = DispatchQueue(label: "com.hisohiso.sinew", qos: .utility)

    /// Whether Sinew is available (socket exists).
    /// Protected by `queue` — use `isAvailable` computed property for thread-safe reads.
    private var _isAvailable = false

    /// Thread-safe check for Sinew availability.
    var isAvailable: Bool {
        queue.sync { _isAvailable }
    }

    /// Unix socket path for Sinew IPC.
    private var socketPath: String {
        let runtimeDir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "/tmp"
        return runtimeDir + "/sinew.sock"
    }

    /// Whether to use Sinew for visualization.
    /// Stored in UserDefaults with backward compatibility for legacy RustyBar key.
    var useSinewVisualization: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: "useSinewVisualization") as? Bool {
                return value
            }
            return UserDefaults.standard.object(forKey: "useRustyBarVisualization") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "useSinewVisualization")
            // Keep legacy key in sync for migration safety.
            UserDefaults.standard.set(newValue, forKey: "useRustyBarVisualization")
        }
    }

    /// Whether to show the floating pill.
    /// Stored in UserDefaults.
    var showFloatingPill: Bool {
        get { UserDefaults.standard.bool(forKey: "showFloatingPill") }
        set { UserDefaults.standard.set(newValue, forKey: "showFloatingPill") }
    }

    /// Should we show the floating pill based on settings?
    var shouldShowFloatingPill: Bool {
        showFloatingPill
    }

    /// Should we send state updates to Sinew based on settings?
    var shouldUseSinew: Bool {
        isAvailable && useSinewVisualization
    }

    /// Backward-compatible alias for legacy callers.
    var useRustyBarVisualization: Bool {
        get { useSinewVisualization }
        set { useSinewVisualization = newValue }
    }

    /// Backward-compatible alias for legacy callers.
    var shouldUseRustyBar: Bool {
        shouldUseSinew
    }

    private init() {
        if UserDefaults.standard.object(forKey: "useSinewVisualization") == nil {
            let legacy = UserDefaults.standard.object(forKey: "useRustyBarVisualization") as? Bool
            UserDefaults.standard.set(legacy ?? true, forKey: "useSinewVisualization")
        }
        if UserDefaults.standard.object(forKey: "showFloatingPill") == nil {
            UserDefaults.standard.set(false, forKey: "showFloatingPill")
        }
        checkAvailability()
    }

    // MARK: - Public API

    /// Send current state to Sinew.
    /// - Parameter state: The recording state.
    func sendState(_ state: RecordingState) {
        guard useSinewVisualization else { return }

        switch state {
        case .idle:
            send("set \(moduleID) drawing=off")
        case .recording:
            send("set \(moduleID) drawing=on label=● color=#ff5555")
        case .transcribing:
            send("set \(moduleID) drawing=on label=◐ color=#f9e2af")
        case .error:
            send("set \(moduleID) drawing=on label=✗ color=#ff5555")
        }
    }

    /// No-op: Sinew external modules do not expose a waveform API.
    /// Audio levels are rendered by `FloatingPillWindow` instead; this method
    /// exists only to keep the call site in `DictationController` uniform.
    func sendAudioLevels(_ levels: [UInt8]) {}

    /// Check if Sinew socket is available.
    func checkAvailability() {
        queue.async { [weak self] in
            guard let self else { return }
            self._isAvailable = FileManager.default.fileExists(atPath: self.socketPath)

            if self._isAvailable {
                logDebug("Sinew socket available at \(self.socketPath)")
            }
        }
    }

    // MARK: - Private

    private func send(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }

            if !self._isAvailable {
                self._isAvailable = FileManager.default.fileExists(atPath: self.socketPath)
            }
            guard self._isAvailable else { return }

            let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else {
                logDebug("Sinew: Failed to create socket")
                return
            }
            defer { close(socket) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = self.socketPath.utf8CString
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            guard pathBytes.count <= maxLen else {
                logError("Sinew: Socket path too long (\(pathBytes.count) > \(maxLen))")
                return
            }
            pathBytes.withUnsafeBufferPointer { src in
                withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                    dest.update(from: src.baseAddress!, count: src.count)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connectResult == 0 else {
                logDebug("Sinew: Failed to connect")
                self._isAvailable = false
                return
            }

            let message = command + "\n"
            message.withCString { ptr in
                _ = Darwin.write(socket, ptr, strlen(ptr))
            }

            logDebug("Sinew: sent '\(command)'")
        }
    }
}

/// Backward-compatible alias while callers migrate from RustyBar naming.
typealias RustyBarBridge = SinewBridge

// MARK: - Audio Level Calculator

extension SinewBridge {
    /// Calculate waveform levels from audio samples.
    /// - Parameter samples: Raw audio samples (16kHz mono).
    /// - Returns: Array of 7 normalized levels (0-100).
    static func calculateAudioLevels(from samples: [Float]) -> [UInt8] {
        guard !samples.isEmpty else {
            return [UInt8](repeating: 0, count: 7)
        }

        let numBars = 7
        let chunkSize = max(1, samples.count / numBars)

        var levels = [UInt8]()

        for i in 0 ..< numBars {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)

            if start < samples.count {
                let chunk = samples[start ..< end]

                // Calculate RMS for this chunk.
                let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))

                // Normalize to 0-100 (raw values, UI will amplify as needed).
                let normalized = min(100, max(0, Int(rms * 300)))
                levels.append(UInt8(normalized))
            } else {
                levels.append(0)
            }
        }

        return levels
    }
}
