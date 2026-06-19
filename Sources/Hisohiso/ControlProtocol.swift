import Foundation

/// Control commands accepted by Hisohiso's local Unix-socket API.
enum ControlMethod: String, Codable {
    case cancel
    case ping
    case start
    case status
    case stop
}

/// JSON request payload sent over the control socket.
struct ControlRequest: Codable {
    let id: String
    let method: ControlMethod
    let params: ControlRequestParams?

    /// Build a request with a generated identifier.
    /// - Parameters:
    ///   - method: Control method to execute.
    ///   - params: Optional method parameters.
    /// - Returns: Request payload with a UUID id.
    static func make(
        method: ControlMethod,
        params: ControlRequestParams? = nil
    ) -> ControlRequest {
        ControlRequest(id: UUID().uuidString, method: method, params: params)
    }
}

/// Optional parameters for control requests.
struct ControlRequestParams: Codable {
    /// Optional model override used by the `start` command.
    let model: String?
}

/// Result payload returned by control API commands.
struct ControlResult: Codable {
    /// Current recorder state.
    let state: ControlState

    /// Error message when state is `.error`.
    let message: String?

    /// Final transcript text returned by `stop`.
    let text: String?

    /// Active transcription model ID.
    let model: String?
}

/// JSON response payload returned over the control socket.
struct ControlResponse: Codable {
    let id: String
    let ok: Bool
    let result: ControlResult?
    let error: String?

    /// Build a success response.
    /// - Parameters:
    ///   - id: Request id to correlate responses.
    ///   - result: Optional command payload.
    /// - Returns: Successful response object.
    static func success(id: String, result: ControlResult? = nil) -> ControlResponse {
        ControlResponse(id: id, ok: true, result: result, error: nil)
    }

    /// Build a failure response.
    /// - Parameters:
    ///   - id: Request id to correlate responses.
    ///   - error: Human-readable error message.
    /// - Returns: Failed response object.
    static func failure(id: String, error: String) -> ControlResponse {
        ControlResponse(id: id, ok: false, result: nil, error: error)
    }
}

/// Normalized recording states exposed by the control API.
enum ControlState: String, Codable {
    case error
    case idle
    case recording
    case transcribing

    /// Convert an internal `RecordingState` to control-protocol state.
    /// - Parameter state: Internal recording state.
    init(from state: RecordingState) {
        switch state {
        case .idle:
            self = .idle
        case .recording:
            self = .recording
        case .transcribing:
            self = .transcribing
        case .error:
            self = .error
        }
    }
}

extension RecordingState {
    /// Extract an optional error message from a recording state.
    var controlMessage: String? {
        if case let .error(message) = self {
            return message
        }
        return nil
    }
}
