import Darwin
import Foundation

@MainActor
extension AppDelegate {
    /// Execute a headless CLI command.
    /// - Parameter command: Parsed CLI command.
    /// - Returns: Process exit code.
    func runCLICommand(_ command: CLICommand) async -> Int32 {
        switch command {
        case .help:
            print(CLIArguments.usage(executableName: CLIArguments.executableName(from: CommandLine.arguments)))
            return 0

        case .version:
            print(CLIArguments.versionString())
            return 0

        case .listModels:
            for model in TranscriptionModel.allCases {
                print("\(model.rawValue)\t\(model.displayName)")
            }
            return 0

        case let .transcribe(duration, model, rawOutput):
            return await runHeadlessTranscription(duration: duration, model: model, rawOutput: rawOutput)

        case let .control(controlCommand):
            return runControlCommand(controlCommand)
        }
    }

    /// Record audio and print a transcription to stdout.
    /// - Parameters:
    ///   - duration: Optional duration in seconds. If `nil`, waits for Enter in an interactive terminal.
    ///   - model: Optional model override for this invocation.
    ///   - rawOutput: Whether to skip smart text formatting.
    /// - Returns: Process exit code.
    private func runHeadlessTranscription(
        duration: TimeInterval?,
        model: TranscriptionModel?,
        rawOutput: Bool
    ) async -> Int32 {
        if duration == nil, !isInteractiveStdin() {
            writeCLIError("--transcribe without <seconds> requires an interactive terminal.")
            return 2
        }

        let selectedModel = model ?? .defaultModel

        writeCLIError("Loading model: \(selectedModel.rawValue)")

        let transcriber = Transcriber()
        do {
            try await transcriber.initialize(model: selectedModel)
        } catch {
            writeCLIError("Failed to initialize model: \(error.localizedDescription)")
            return 1
        }

        let hasMicrophonePermission = await AudioRecorder.requestPermission()
        guard hasMicrophonePermission else {
            writeCLIError("Microphone permission denied.")
            return 1
        }

        let recorder = AudioRecorder()
        do {
            try recorder.startRecording()
        } catch {
            writeCLIError("Failed to start recording: \(error.localizedDescription)")
            return 1
        }

        if let duration {
            writeCLIError("Recording for \(String(format: "%.1f", duration)) seconds...")
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                recorder.cancelRecording()
                writeCLIError("Recording cancelled")
                return 130
            }
        } else {
            writeCLIError("Recording... press Enter to stop.")
            await waitForEnterKey()
        }

        let audioSamples = recorder.stopRecording()
        guard audioSamples.count >= AppConstants.minTranscriptionSamples else {
            writeCLIError("Recording too short for transcription.")
            return 1
        }

        do {
            let rawText = try await transcriber.transcribe(audioSamples)
            if rawText.isEmpty {
                writeCLIError("No transcription produced.")
                return 1
            }

            let output = rawOutput ? rawText : TextFormatter().format(rawText)
            print(output)
            return 0
        } catch {
            writeCLIError("Transcription failed: \(error.localizedDescription)")
            return 1
        }
    }

    /// Execute a control command against a running Hisohiso instance.
    /// - Parameter command: Parsed control command.
    /// - Returns: Process exit code.
    private func runControlCommand(_ command: CLIControlCommand) -> Int32 {
        let request: ControlRequest
        let timeout: TimeInterval
        switch command {
        case .ping:
            request = ControlRequest.make(method: .ping)
            timeout = 2.0
        case .status:
            request = ControlRequest.make(method: .status)
            timeout = 2.0
        case let .start(model):
            let params = ControlRequestParams(model: model?.rawValue)
            request = ControlRequest.make(method: .start, params: params)
            // A model override may trigger a download/load before recording starts.
            timeout = model == nil
                ? AppConstants.transcriptionTimeout + 60
                : 300
        case .stop:
            request = ControlRequest.make(method: .stop)
            // `stop` runs full transcription, up to `transcriptionTimeout`.
            timeout = AppConstants.transcriptionTimeout + 60
        case .cancel:
            request = ControlRequest.make(method: .cancel)
            timeout = 2.0
        }

        switch ControlSocketClient.send(request: request, timeout: timeout) {
        case let .success(response):
            printControlResponse(response)
            return response.ok ? 0 : 1
        case let .failure(error):
            let response = Self.makeControlFailureResponse(requestID: request.id, error: error)
            printControlResponse(response)
            return 1
        }
    }

    /// Build a machine-readable failure response for local transport errors.
    /// - Parameters:
    ///   - requestID: Original request identifier.
    ///   - error: Transport/client error.
    /// - Returns: JSON response payload matching the control protocol shape.
    nonisolated static func makeControlFailureResponse(
        requestID: String,
        error: ControlSocketClientError
    ) -> ControlResponse {
        let message: String = if case .connectFailed = error {
            "\(error.localizedDescription). Start Hisohiso first (open -a Hisohiso), then retry."
        } else {
            error.localizedDescription
        }

        return ControlResponse.failure(id: requestID, error: message)
    }

    /// Print a JSON control response to stdout.
    /// - Parameter response: Control response payload.
    private func printControlResponse(_ response: ControlResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(response),
           let line = String(data: data, encoding: .utf8)
        {
            print(line)
        } else {
            print("{\"ok\":false,\"error\":\"Failed to encode response\"}")
        }
    }

    /// Return whether stdin is connected to a terminal.
    /// - Returns: `true` if stdin is a TTY.
    private func isInteractiveStdin() -> Bool {
        isatty(fileno(stdin)) != 0
    }

    /// Wait for the user to press Enter.
    private func waitForEnterKey() async {
        _ = await Task.detached(priority: .utility) {
            readLine(strippingNewline: true)
        }.value
    }

    /// Write a CLI message to stderr.
    /// - Parameter message: Message to write.
    func writeCLIError(_ message: String) {
        let data = Data("\(message)\n".utf8)
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
