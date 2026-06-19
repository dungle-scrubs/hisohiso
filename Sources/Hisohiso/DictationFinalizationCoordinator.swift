import Foundation

/// Coordinates dictation finalization side effects after recording stops.
///
/// `DictationController` owns the high-level FSM. This coordinator owns the
/// repeated finish/cleanup decisions: exactly one idle transition for non-error
/// exits, history persistence on success, insertion behavior for cursor mode,
/// and text-only behavior for external control.
struct DictationFinalizationCoordinator {
    var textFormatter: TextFormatter
    var setIdle: () -> Void
    var setError: (String) -> Void
    var saveHistory: (_ text: String, _ duration: TimeInterval, _ modelName: String) -> Void
    var insertText: (String) throws -> Void

    func failIdle(_ error: ControlledTranscriptionError) -> Result<String, ControlledTranscriptionError> {
        setIdle()
        return .failure(error)
    }

    func finishSuccess(
        rawText: String,
        duration: TimeInterval,
        mode: TranscriptionOutputMode,
        modelName: String
    ) -> Result<String, ControlledTranscriptionError> {
        guard !rawText.isEmpty else {
            logInfo("Empty transcription result")
            return failIdle(.emptyTranscription)
        }

        let formattedText = textFormatter.format(rawText)
        logInfo("Formatted: '\(rawText)' → '\(formattedText)'")
        saveHistory(formattedText, duration, modelName)

        if mode == .insertAtCursor {
            do {
                try insertText(formattedText)
            } catch {
                logError("Failed to insert text at cursor: \(error)")
                setError(error.localizedDescription)
                return .failure(.textInsertionFailed(error.localizedDescription))
            }
        }

        setIdle()
        return .success(formattedText)
    }
}
