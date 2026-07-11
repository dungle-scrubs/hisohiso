import Foundation

// MARK: - Transcription Flow

extension DictationController {
    /// Shared recording stop/transcription flow used by both UI and external control.
    /// - Parameter mode: Output behavior after transcription.
    /// - Returns: Formatted text or a typed control error.
    func stopRecordingAndTranscribe(
        mode: TranscriptionOutputMode
    ) async -> Result<String, ControlledTranscriptionError> {
        guard stateManager.isRecording else {
            logWarning("Cannot stop recording: not recording")
            return .failure(.notRecording)
        }

        stopAudioLevelUpdates()
        // Send zero levels to clear the waveform before the stop sound plays.
        audioLevelPublisher.clearLevels()
        stopEscapeMonitor()
        audioFeedback.playStop()

        let audioSamples = activeRecorder.stopRecording()
        mediaPlaybackCoordinator.resumeAfterRecording()

        waveformBridge.sendState(.transcribing)

        // Calculate recording duration.
        let duration: TimeInterval = if let startTime = recordingStartTime {
            Date().timeIntervalSince(startTime)
        } else {
            Double(audioSamples.count) / AppConstants.targetSampleRate
        }
        recordingStartTime = nil

        guard !audioSamples.isEmpty else {
            logWarning("No audio captured")
            return finalizationCoordinator().failIdle(.noAudioCaptured)
        }

        // Minimum audio length check — the 1s floor is a Parakeet/FluidAudio
        // requirement. WhisperKit handles sub-second clips, so only gate the
        // Parakeet backend and let shorter WhisperKit clips through.
        if modelManager.selectedModel.backend == .parakeet,
           audioSamples.count < AppConstants.minTranscriptionSamples {
            logInfo(
                "Audio too short (\(audioSamples.count) samples, need \(AppConstants.minTranscriptionSamples)), ignoring"
            )
            return finalizationCoordinator().failIdle(.audioTooShort)
        }

        stateManager.setTranscribing()

        #if DEBUG
        saveDebugAudio(audioSamples)
        #endif

        switch await verifyVoiceIfNeeded(audioSamples: audioSamples) {
        case .success:
            break
        case let .failure(.voiceVerificationError(message)):
            // A thrown verifier error fails closed to a distinct, user-visible
            // error state (not a silent idle) so the bypass is never invisible.
            logError("Blocking transcription: voice verification error")
            waveformBridge.sendState(.error(message: "Voice check failed"))
            stateManager.setError("Voice verification failed to run")
            return .failure(.voiceVerificationError(message))
        case let .failure(error):
            return finalizationCoordinator().failIdle(error)
        }

        do {
            let rawText = try await transcriber.transcribe(audioSamples)
            return finishSuccessfulTranscription(rawText: rawText, duration: duration, mode: mode)
        } catch let error as TranscriberError {
            logError("Transcription error: \(error)")
            switch error {
            case .timeout:
                waveformBridge.sendState(.error(message: "Timed out"))
                stateManager.setError("Transcription timed out")
                return .failure(.transcriptionFailed("Transcription timed out"))
            case .invalidAudioData:
                logInfo("Audio too short for transcription")
                return finalizationCoordinator().failIdle(.audioTooShort)
            default:
                waveformBridge.sendState(.error(message: error.localizedDescription))
                stateManager.setError(error.localizedDescription)
                return .failure(.transcriptionFailed(error.localizedDescription))
            }
        } catch {
            logError("Error during transcription: \(error)")
            waveformBridge.sendState(.error(message: error.localizedDescription))
            stateManager.setError(error.localizedDescription)
            return .failure(.transcriptionFailed(error.localizedDescription))
        }
    }

    /// Perform optional speaker verification before transcription.
    /// - Parameter audioSamples: Captured microphone audio.
    /// - Returns: Success when verification passes or is disabled.
    private func verifyVoiceIfNeeded(audioSamples: [Float]) async -> Result<Void, ControlledTranscriptionError> {
        guard voiceVerifier.isEnabled, voiceVerifier.isEnrolled else {
            return .success(())
        }

        do {
            let verificationResult = try await voiceVerifier.verify(audioSamples: audioSamples)
            if !verificationResult.isMatch {
                logInfo(
                    "Voice verification failed (similarity: \(String(format: "%.2f", verificationResult.similarity)))"
                )
                return .failure(.voiceVerificationFailed)
            }

            logDebug("Voice verified (similarity: \(String(format: "%.2f", verificationResult.similarity)))")
            return .success(())
        } catch {
            // Fail CLOSED: a verifier error must not silently bypass the speaker
            // gate. Block transcription/insertion and surface a distinct error.
            logError("Voice verification error: \(error.localizedDescription)")
            return .failure(.voiceVerificationError(error.localizedDescription))
        }
    }

    private func finalizationCoordinator() -> DictationFinalizationCoordinator {
        DictationFinalizationCoordinator(
            textFormatter: textFormatter,
            setIdle: { [stateManager] in stateManager.setIdle() },
            setError: { [stateManager] message in stateManager.setError(message) },
            sendState: { [waveformBridge] state in waveformBridge.sendState(state) },
            saveHistory: { [historyStore] text, duration, modelName in
                historyStore.save(text: text, duration: duration, modelName: modelName)
            },
            insertText: { [textInserter] text in try textInserter.insert(text) }
        )
    }

    /// Persist and emit a successful transcription.
    /// - Parameters:
    ///   - rawText: Raw text from the speech model.
    ///   - duration: Recording duration in seconds.
    ///   - mode: Output behavior after formatting.
    /// - Returns: Formatted transcription text.
    private func finishSuccessfulTranscription(
        rawText: String,
        duration: TimeInterval,
        mode: TranscriptionOutputMode
    ) -> Result<String, ControlledTranscriptionError> {
        finalizationCoordinator().finishSuccess(
            rawText: rawText,
            duration: duration,
            mode: mode,
            modelName: modelManager.selectedModel.displayName
        )
    }

    #if DEBUG
    /// Save audio samples to file for debugging, pruning old files.
    func saveDebugAudio(_ samples: [Float]) {
        let debugDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hisohiso-debug")
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = debugDir.appendingPathComponent("\(timestamp).raw")

        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        do {
            try data.write(to: path)
            logInfo("Debug audio saved to \(path.path) (\(samples.count) samples)")
            pruneDebugAudio(in: debugDir)
        } catch {
            logError("Failed to save debug audio: \(error)")
        }
    }

    /// Keep only the most recent debug audio files.
    private func pruneDebugAudio(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .sorted(by: { ($0.lastPathComponent) > ($1.lastPathComponent) })
        else { return }

        for file in files.dropFirst(AppConstants.maxDebugAudioFiles) {
            try? fm.removeItem(at: file)
        }
    }
    #endif
}
