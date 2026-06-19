import Foundation

/// Queue-confined connection state for the external waveform display bridge.
///
/// `WaveformBridge` performs socket I/O on a serial queue. This value centralizes
/// the mutable connection metadata so replay, availability, and retry behavior
/// are explicit and separately testable.
struct WaveformConnectionStore: Sendable {
    private(set) var socketFD: Int32 = -1
    private(set) var latestStateCommand = "state idle"
    private(set) var isAvailable = false

    var isConnected: Bool { socketFD >= 0 }

    mutating func markAvailable(_ available: Bool) {
        isAvailable = available
    }

    mutating func connect(fd: Int32) {
        socketFD = fd
        isAvailable = true
    }

    mutating func disconnect() -> Int32? {
        guard socketFD >= 0 else {
            isAvailable = false
            return nil
        }
        let fd = socketFD
        socketFD = -1
        isAvailable = false
        return fd
    }

    mutating func recordStateCommand(_ command: String) {
        latestStateCommand = command
    }
}
