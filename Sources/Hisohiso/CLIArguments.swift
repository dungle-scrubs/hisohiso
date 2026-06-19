import Foundation

/// Startup behavior for the `hisohiso` executable.
enum LaunchMode: Equatable {
    /// Launch the menu bar app.
    ///
    /// - Parameter showHistoryOnLaunch: Whether to open the history palette after startup.
    case app(showHistoryOnLaunch: Bool)

    /// Run a headless CLI command, then exit.
    ///
    /// - Parameter command: The parsed CLI command.
    case cli(command: CLICommand)
}

/// Control commands sent to the local Unix-socket API.
enum CLIControlCommand: Equatable {
    case cancel
    case ping
    case start(model: TranscriptionModel?)
    case status
    case stop
}

/// Headless CLI commands supported by `hisohiso`.
enum CLICommand: Equatable {
    /// Print usage text.
    case help

    /// Print app version.
    case version

    /// Print supported model identifiers.
    case listModels

    /// Record audio and print transcription to stdout.
    ///
    /// - Parameters:
    ///   - duration: Optional recording duration in seconds. If `nil`, interactive mode records until Enter.
    ///   - model: Optional model override for this invocation.
    ///   - rawOutput: Whether to skip smart formatting.
    case transcribe(duration: TimeInterval?, model: TranscriptionModel?, rawOutput: Bool)

    /// Send a control command to a running Hisohiso instance.
    case control(CLIControlCommand)
}

/// Parse errors for CLI launch arguments.
enum CLIArgumentError: Error, Equatable, LocalizedError {
    case conflictingCommands
    case invalidControlCommand(String)
    case invalidDuration(String)
    case invalidModel(String)
    case missingControlCommand
    case missingTranscribeFlag
    case missingValue(String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .conflictingCommands:
            "Conflicting launch arguments. Use either app mode flags or one CLI command."
        case let .invalidControlCommand(command):
            "Unknown control command '\(command)'. Use one of: ping, status, start, stop, cancel."
        case let .invalidDuration(value):
            "Invalid duration '\(value)'. Use a positive number of seconds."
        case let .invalidModel(model):
            "Unknown model '\(model)'. Use --list-models to see valid IDs."
        case .missingControlCommand:
            "Missing control command. Use: hisohiso ctl <ping|status|start|stop|cancel>."
        case .missingTranscribeFlag:
            "--model and --raw require --transcribe."
        case let .missingValue(option):
            "Missing value for \(option)"
        case let .unknownOption(option):
            "Unknown option: \(option)"
        }
    }
}

/// Parser and help text for command-line arguments.
enum CLIArguments {
    /// Parse launch arguments into app mode or headless command mode.
    ///
    /// - Parameter arguments: Full argument vector including executable path.
    /// - Returns: Parsed `LaunchMode` or a parse error.
    static func parse(_ arguments: [String]) -> Result<LaunchMode, CLIArgumentError> {
        let args = Array(arguments.dropFirst())
        guard !args.isEmpty else {
            return .success(.app(showHistoryOnLaunch: false))
        }

        if args.first == "ctl" {
            return parseControl(args: Array(args.dropFirst()))
        }

        var showHistoryOnLaunch = false
        var simpleCommand: CLICommand?
        var hasTranscribe = false
        var transcribeDuration: TimeInterval?
        var transcribeModel: TranscriptionModel?
        var rawOutput = false

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch arg {
            case "--history":
                showHistoryOnLaunch = true

            case "-h", "--help":
                simpleCommand = .help

            case "--version":
                simpleCommand = .version

            case "--list-models":
                simpleCommand = .listModels

            case "--raw":
                rawOutput = true

            case "--transcribe":
                hasTranscribe = true

                // Optional duration: if next token is a value (not another flag), parse seconds.
                if index + 1 < args.count {
                    let token = args[index + 1]
                    if !token.hasPrefix("-") {
                        guard let duration = TimeInterval(token), duration > 0 else {
                            return .failure(.invalidDuration(token))
                        }
                        transcribeDuration = duration
                        index += 1
                    }
                }

            case "--model":
                guard index + 1 < args.count else {
                    return .failure(.missingValue("--model"))
                }

                let token = args[index + 1]
                guard let model = TranscriptionModel(rawValue: token) else {
                    return .failure(.invalidModel(token))
                }

                transcribeModel = model
                index += 1

            default:
                return .failure(.unknownOption(arg))
            }

            index += 1
        }

        if let command = simpleCommand {
            if showHistoryOnLaunch || hasTranscribe || transcribeModel != nil || rawOutput {
                return .failure(.conflictingCommands)
            }
            return .success(.cli(command: command))
        }

        if hasTranscribe {
            if showHistoryOnLaunch {
                return .failure(.conflictingCommands)
            }

            return .success(.cli(command: .transcribe(
                duration: transcribeDuration,
                model: transcribeModel,
                rawOutput: rawOutput
            )))
        }

        if transcribeModel != nil || rawOutput {
            return .failure(.missingTranscribeFlag)
        }

        return .success(.app(showHistoryOnLaunch: showHistoryOnLaunch))
    }

    /// Parse `hisohiso ctl ...` arguments.
    ///
    /// - Parameter args: Arguments after the `ctl` token.
    /// - Returns: Parsed launch mode with control command.
    private static func parseControl(args: [String]) -> Result<LaunchMode, CLIArgumentError> {
        guard let command = args.first else {
            return .failure(.missingControlCommand)
        }

        var modelOverride: TranscriptionModel?
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--model":
                guard index + 1 < args.count else {
                    return .failure(.missingValue("--model"))
                }

                let token = args[index + 1]
                guard let model = TranscriptionModel(rawValue: token) else {
                    return .failure(.invalidModel(token))
                }
                modelOverride = model
                index += 1

            default:
                return .failure(.unknownOption(arg))
            }

            index += 1
        }

        switch command {
        case "ping":
            guard modelOverride == nil else {
                return .failure(.conflictingCommands)
            }
            return .success(.cli(command: .control(.ping)))
        case "status":
            guard modelOverride == nil else {
                return .failure(.conflictingCommands)
            }
            return .success(.cli(command: .control(.status)))
        case "start":
            return .success(.cli(command: .control(.start(model: modelOverride))))
        case "stop":
            guard modelOverride == nil else {
                return .failure(.conflictingCommands)
            }
            return .success(.cli(command: .control(.stop)))
        case "cancel":
            guard modelOverride == nil else {
                return .failure(.conflictingCommands)
            }
            return .success(.cli(command: .control(.cancel)))
        default:
            return .failure(.invalidControlCommand(command))
        }
    }

    /// Build user-facing usage text.
    ///
    /// - Parameter executableName: Binary name to show in examples.
    /// - Returns: Multiline usage text.
    static func usage(executableName: String) -> String {
        let modelList = TranscriptionModel.allCases
            .map { "  \($0.rawValue)" }
            .joined(separator: "\n")

        return """
        Usage:
          \(executableName)                         Launch menu bar app
          \(executableName) --history               Launch app and open history palette

          \(executableName) --help                    Show this help
          \(executableName) --version                 Print version
          \(executableName) --list-models             List available model IDs
          \(executableName) --transcribe              Record until Enter (interactive)
          \(executableName) --transcribe <seconds>    Record for fixed duration
          \(executableName) --transcribe [seconds] --model <id> [--raw]

          \(executableName) ctl ping                  Check control server availability
          \(executableName) ctl status                Read current recording state
          \(executableName) ctl start [--model <id>]  Start recording
          \(executableName) ctl stop                  Stop recording and return text
          \(executableName) ctl cancel                Cancel active recording

        Notes:
          --transcribe prints to stdout (pipe-friendly)
          --transcribe without <seconds> requires an interactive TTY
          ctl commands print JSON for machine-readable integration
          --raw skips smart formatting (capitalization/filler cleanup)

        Model IDs:
        \(modelList)
        """
    }

    /// Resolve the executable display name from argv.
    ///
    /// - Parameter arguments: Full argument vector including executable path.
    /// - Returns: Basename of argv[0], or "hisohiso" fallback.
    static func executableName(from arguments: [String]) -> String {
        guard let first = arguments.first, !first.isEmpty else {
            return "hisohiso"
        }

        return URL(fileURLWithPath: first).lastPathComponent
    }

    /// Resolve a printable version string.
    ///
    /// - Returns: App bundle short version, or "dev" fallback.
    static func versionString() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let shortVersion, !shortVersion.isEmpty {
            return shortVersion
        }
        return "dev"
    }
}
