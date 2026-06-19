import Foundation

@MainActor
protocol DictationControlHandling: AnyObject {
    var controlRecordingState: RecordingState { get }
    var isControlIdle: Bool { get }
    var isControlRecording: Bool { get }
    func startControlRecording() async
    func stopControlRecording() async -> Result<String, ControlledTranscriptionError>
    func cancelControlRecording()
}

/// Handles parsed control commands without owning the Unix-socket transport.
@MainActor
final class ControlCommandService {
    private let dictationController: () -> (any DictationControlHandling)?
    private let modelSelectionController: ModelSelectionController

    init(
        modelSelectionController: ModelSelectionController,
        dictationController: @escaping () -> (any DictationControlHandling)?
    ) {
        self.modelSelectionController = modelSelectionController
        self.dictationController = dictationController
    }

    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request.method {
        case .ping:
            ControlResponse.success(id: request.id, result: currentControlResult())
        case .status:
            handleStatus(request)
        case .start:
            await handleStart(request)
        case .stop:
            await handleStop(request)
        case .cancel:
            handleCancel(request)
        }
    }

    private func handleStatus(_ request: ControlRequest) -> ControlResponse {
        guard dictationController() != nil else {
            return ControlResponse.failure(id: request.id, error: "Dictation controller not ready")
        }

        return ControlResponse.success(id: request.id, result: currentControlResult())
    }

    private func handleStart(_ request: ControlRequest) async -> ControlResponse {
        guard let controller = dictationController() else {
            return ControlResponse.failure(id: request.id, error: "Dictation controller not ready")
        }

        guard controller.isControlIdle else {
            return ControlResponse.failure(id: request.id, error: "Recorder is busy")
        }

        if let modelID = request.params?.model {
            guard let requestedModel = TranscriptionModel(rawValue: modelID) else {
                return ControlResponse.failure(id: request.id, error: "Unknown model: \(modelID)")
            }

            do {
                try await modelSelectionController.requestSelection(requestedModel, reloadPolicy: .immediately)
            } catch {
                return ControlResponse.failure(id: request.id, error: error.localizedDescription)
            }
        }

        await controller.startControlRecording()

        guard controller.isControlRecording else {
            return ControlResponse.failure(id: request.id, error: "Failed to start recording")
        }

        return ControlResponse.success(id: request.id, result: currentControlResult())
    }

    private func handleStop(_ request: ControlRequest) async -> ControlResponse {
        guard let controller = dictationController() else {
            return ControlResponse.failure(id: request.id, error: "Dictation controller not ready")
        }

        switch await controller.stopControlRecording() {
        case let .success(text):
            return ControlResponse.success(id: request.id, result: currentControlResult(text: text))
        case let .failure(error):
            return ControlResponse.failure(id: request.id, error: error.localizedDescription)
        }
    }

    private func handleCancel(_ request: ControlRequest) -> ControlResponse {
        guard let controller = dictationController() else {
            return ControlResponse.failure(id: request.id, error: "Dictation controller not ready")
        }

        controller.cancelControlRecording()
        return ControlResponse.success(id: request.id, result: currentControlResult())
    }

    private func currentControlResult(text: String? = nil) -> ControlResult {
        let state = dictationController()?.controlRecordingState ?? .idle
        return ControlResult(
            state: ControlState(from: state),
            message: state.controlMessage,
            text: text,
            model: modelSelectionController.selectedModel.rawValue
        )
    }
}
