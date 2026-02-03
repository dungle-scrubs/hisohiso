import Foundation

/// Bridge to communicate with RustyBar's Hisohiso module via Unix socket
final class RustyBarBridge {
    static let shared = RustyBarBridge()

    private let socketPath = "/tmp/hisohiso-rustybar.sock"
    private let commandSocketPath = "/tmp/hisohiso-command.sock"
    private let queue = DispatchQueue(label: "com.hisohiso.rustybar", qos: .utility)

    /// Whether RustyBar is available (socket exists)
    private(set) var isAvailable = false

    /// Whether to use RustyBar for visualization
    /// Stored in UserDefaults
    var useRustyBarVisualization: Bool {
        get { UserDefaults.standard.bool(forKey: "useRustyBarVisualization") }
        set { UserDefaults.standard.set(newValue, forKey: "useRustyBarVisualization") }
    }

    /// Whether to show the floating pill
    /// Stored in UserDefaults
    var showFloatingPill: Bool {
        get { UserDefaults.standard.bool(forKey: "showFloatingPill") }
        set { UserDefaults.standard.set(newValue, forKey: "showFloatingPill") }
    }

    /// Should we show the floating pill based on settings?
    var shouldShowFloatingPill: Bool {
        showFloatingPill
    }

    /// Should we send to RustyBar based on settings?
    var shouldUseRustyBar: Bool {
        isAvailable && useRustyBarVisualization
    }

    private init() {
        // Default: RustyBar on if available, pill off
        if UserDefaults.standard.object(forKey: "useRustyBarVisualization") == nil {
            UserDefaults.standard.set(true, forKey: "useRustyBarVisualization")
        }
        if UserDefaults.standard.object(forKey: "showFloatingPill") == nil {
            UserDefaults.standard.set(false, forKey: "showFloatingPill")
        }
        checkAvailability()
    }

    // MARK: - Public API

    /// Send current state to RustyBar
    /// - Parameter state: The recording state
    func sendState(_ state: RecordingState) {
        let stateStr: String
        switch state {
        case .idle:
            stateStr = "idle"
        case .recording:
            stateStr = "recording"
        case .transcribing:
            stateStr = "transcribing"
        case .error:
            stateStr = "error"
        }

        send("state \(stateStr)")
    }

    /// Send audio levels to RustyBar for waveform visualization
    /// - Parameter levels: Array of 7 audio levels (0-100)
    func sendAudioLevels(_ levels: [UInt8]) {
        guard levels.count >= 7 else { return }

        let levelsStr = levels.prefix(7).map { String($0) }.joined(separator: ",")
        send("levels \(levelsStr)")
    }

    /// Check if RustyBar socket is available
    func checkAvailability() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isAvailable = FileManager.default.fileExists(atPath: self.socketPath)

            if self.isAvailable {
                logDebug("RustyBar socket available at \(self.socketPath)")
            }
        }
    }

    // MARK: - Private

    private func send(_ command: String) {
        queue.async { [weak self] in
            guard let self, self.isAvailable else { return }

            let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else {
                logDebug("RustyBar: Failed to create socket")
                return
            }
            defer { close(socket) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            self.socketPath.withCString { ptr in
                withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                    _ = strcpy(dest, ptr)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connectResult == 0 else {
                logDebug("RustyBar: Failed to connect")
                self.isAvailable = false
                return
            }

            let message = command + "\n"
            message.withCString { ptr in
                _ = Darwin.write(socket, ptr, strlen(ptr))
            }

            logDebug("RustyBar: sent '\(command)'")
        }
    }
}

// MARK: - Audio Level Calculator

extension RustyBarBridge {
    /// Calculate waveform levels from audio samples
    /// - Parameter samples: Raw audio samples (16kHz mono)
    /// - Returns: Array of 7 normalized levels (0-100)
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

                // Calculate RMS for this chunk
                let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))

                // Normalize to 0-100 (assuming typical speech RMS is 0.01-0.3)
                let normalized = min(100, max(0, Int(rms * 300)))
                levels.append(UInt8(normalized))
            } else {
                levels.append(0)
            }
        }

        return levels
    }
}
