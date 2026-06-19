import Foundation

/// Thread-safe state store for `AudioRecorder` lifecycle and sample buffer.
///
/// Audio render callbacks and main-thread recorder controls both touch recorder
/// state. This store provides one explicit lock boundary for lifecycle state and
/// captured samples so `AudioRecorder` does not scatter lock discipline across
/// unrelated methods.
final class AudioRecorderStateStore: @unchecked Sendable {
    /// Recorder lifecycle states. Transitions:
    /// `idle` → `monitoring` → `idle`
    /// `idle` → `recording` → `idle`
    /// `monitoring` → `recordingFromMonitoring` → `monitoring`
    enum Lifecycle: CustomStringConvertible {
        case idle
        case monitoring
        case recording
        case recordingFromMonitoring

        var description: String {
            switch self {
            case .idle: "idle"
            case .monitoring: "monitoring"
            case .recording: "recording"
            case .recordingFromMonitoring: "recordingFromMonitoring"
            }
        }
    }

    private let lock = NSLock()
    private var lifecycle: Lifecycle = .idle
    private var samples: [Float] = []

    /// Read the current recorder lifecycle state.
    /// - Returns: Current lifecycle state.
    func state() -> Lifecycle {
        lock.withLock { lifecycle }
    }

    /// Replace the current recorder lifecycle state.
    /// - Parameter state: New lifecycle state.
    func setState(_ state: Lifecycle) {
        lock.withLock { lifecycle = state }
    }

    /// Remove all buffered samples.
    func clearSamples() {
        lock.withLock { samples.removeAll() }
    }

    /// Drain buffered samples and clear the store.
    /// - Returns: Samples captured before the drain.
    func drainSamples() -> [Float] {
        lock.withLock {
            let captured = samples
            samples.removeAll()
            return captured
        }
    }

    /// Return the most recent captured samples.
    /// - Parameter count: Maximum number of samples to return.
    /// - Returns: Suffix of captured samples, or all samples if fewer exist.
    func recentSamples(count: Int) -> [Float] {
        lock.withLock {
            if samples.count <= count {
                return samples
            }
            return Array(samples.suffix(count))
        }
    }

    /// Append samples captured from the audio render callback.
    /// - Parameter newSamples: Samples to append to the capture buffer.
    func appendSamples(_ newSamples: [Float]) {
        lock.withLock {
            samples.append(contentsOf: newSamples)
        }
    }
}
