import Foundation

/// State machine for the recording lifecycle
enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case error(message: String)

    var displayText: String {
        switch self {
        case .idle: return ""
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .error(let message): return message
        }
    }
}

/// Observable state manager for recording
@MainActor
final class RecordingStateManager: ObservableObject {
    @Published private(set) var state: RecordingState = .idle

    /// Callback for retry action from error state
    var onRetry: (() -> Void)?

    func setRecording() {
        state = .recording
        logInfo("State: recording")
    }

    func setTranscribing() {
        state = .transcribing
        logInfo("State: transcribing")
    }

    func setIdle() {
        state = .idle
        logInfo("State: idle")
    }

    func setError(_ message: String) {
        state = .error(message: message)
        logError("State: error - \(message)")
    }

    func retry() {
        onRetry?()
    }

    var isIdle: Bool { state == .idle }
    var isRecording: Bool { state == .recording }
    var isTranscribing: Bool { state == .transcribing }
    var hasError: Bool {
        if case .error = state { return true }
        return false
    }
}
