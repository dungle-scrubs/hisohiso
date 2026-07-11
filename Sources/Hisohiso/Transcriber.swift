import FluidAudio
import Foundation
import WhisperKit

// MARK: - Transcription Backend

/// Transcription backend type
enum TranscriptionBackend: String, CaseIterable, Identifiable {
    case whisper
    case parakeet

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .whisper: "Whisper (WhisperKit)"
        case .parakeet: "Parakeet (FluidAudio)"
        }
    }
}

// MARK: - Transcription Model

/// Transcription model options
enum TranscriptionModel: String, CaseIterable, Identifiable {
    // Whisper models
    case whisperTiny = "openai_whisper-tiny"
    case whisperBase = "openai_whisper-base.en"
    case whisperSmall = "openai_whisper-small.en"
    case whisperLargeV3Turbo = "openai_whisper-large-v3_turbo"
    case whisperDistilLargeV3 = "distil-whisper_distil-large-v3"

    // Parakeet models
    case parakeetV2 = "parakeet-tdt-0.6b-v2"
    case parakeetV3 = "parakeet-tdt-0.6b-v3"

    var id: String {
        rawValue
    }

    var backend: TranscriptionBackend {
        switch self {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperLargeV3Turbo, .whisperDistilLargeV3:
            .whisper
        case .parakeetV2, .parakeetV3:
            .parakeet
        }
    }

    var displayName: String {
        switch self {
        case .whisperTiny: "Whisper Tiny (~66 MB)"
        case .whisperBase: "Whisper Base English (~105 MB)"
        case .whisperSmall: "Whisper Small English (~330 MB)"
        case .whisperLargeV3Turbo: "Whisper Large V3 Turbo (~954 MB)"
        case .whisperDistilLargeV3: "Whisper Distil Large V3 (~800 MB)"
        case .parakeetV2: "Parakeet v2 English (~2.6 GB) ⭐"
        case .parakeetV3: "Parakeet v3 Multilingual (~2.7 GB)"
        }
    }

    var asrModelVersion: AsrModelVersion? {
        switch self {
        case .parakeetV2: .v2
        case .parakeetV3: .v3
        default: nil
        }
    }

    /// Default model - Parakeet v2 for best English accuracy
    static let defaultModel: TranscriptionModel = .parakeetV2

    /// Whisper models only
    static var whisperModels: [TranscriptionModel] {
        allCases.filter { $0.backend == .whisper }
    }

    /// Parakeet models only
    static var parakeetModels: [TranscriptionModel] {
        allCases.filter { $0.backend == .parakeet }
    }
}

// MARK: - Transcriber Error

/// Error types for transcription
enum TranscriberError: Error, LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case warmupFailed(model: String, backend: String, underlying: Error)
    case transcriptionFailed(Error)
    case timeout
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Transcriber not initialized"
        case let .modelNotFound(model):
            "Model not found: \(model)"
        case let .warmupFailed(model, backend, underlying):
            "Warmup failed for \(model) (\(backend)): \(underlying.localizedDescription)"
        case let .transcriptionFailed(error):
            "Transcription failed: \(error.localizedDescription)"
        case .timeout:
            "Transcription timed out"
        case .invalidAudioData:
            "Invalid or too short audio data"
        }
    }
}

// MARK: - Cloud Fallback Settings

/// Cloud fallback configuration
struct CloudFallbackSettings {
    /// Whether to use cloud as fallback when local fails
    var enabled: Bool = false

    /// Preferred cloud provider
    var preferredProvider: CloudProviderType = .openAI

    /// Load from UserDefaults
    static func load(defaults: UserDefaults = .standard) -> CloudFallbackSettings {
        CloudFallbackSettings(
            enabled: defaults.bool(for: .cloudFallbackEnabled),
            preferredProvider: CloudProviderType(
                rawValue: defaults.string(for: .cloudFallbackProvider) ?? "openai"
            ) ?? .openAI
        )
    }

    /// Save to UserDefaults
    func save(defaults: UserDefaults = .standard) {
        defaults.set(enabled, for: .cloudFallbackEnabled)
        defaults.set(preferredProvider.rawValue, for: .cloudFallbackProvider)
    }
}

// MARK: - Transcriber

/// Multi-backend transcription service supporting WhisperKit, FluidAudio (Parakeet), and cloud fallback
actor Transcriber {
    private nonisolated(unsafe) var whisperKit: WhisperKit?
    private nonisolated(unsafe) var asrManager: AsrManager?
    private var currentModel: TranscriptionModel?
    private let timeoutSeconds: TimeInterval = AppConstants.transcriptionTimeout

    /// Cloud providers for fallback, in priority order.
    private let cloudProviders: [(type: CloudProviderType, provider: CloudProvider)] = [
        (.openAI, OpenAIProvider()),
        (.groq, GroqProvider()),
    ]

    /// Cloud fallback settings
    var cloudFallbackSettings = CloudFallbackSettings.load()

    /// Initialize the transcriber with a specific model
    /// - Parameter model: The model to use for transcription
    func initialize(model: TranscriptionModel = .defaultModel) async throws {
        logInfo("Initializing transcriber with model: \(model.rawValue) (backend: \(model.backend.rawValue))")

        // Reset previous state, releasing CoreML models deterministically
        // before dropping the references so memory is reclaimed promptly.
        await whisperKit?.unloadModels()
        whisperKit = nil
        asrManager?.cleanup()
        asrManager = nil

        switch model.backend {
        case .whisper:
            try await initializeWhisper(model: model)
        case .parakeet:
            try await initializeParakeet(model: model)
        }

        currentModel = model
        logInfo("Transcriber initialized with \(model.displayName)")
    }

    private func initializeWhisper(model: TranscriptionModel) async throws {
        do {
            whisperKit = try await WhisperKit(
                model: model.rawValue,
                verbose: false,
                logLevel: .none
            )

            // Warmup with silent audio to prime the Neural Engine
            if let kit = whisperKit {
                let kitBox = UncheckedSendableBox(value: kit)
                logInfo("Warming up WhisperKit...")
                let silentAudio = [Float](repeating: 0, count: 16000) // 1 second of silence
                do {
                    _ = try await kitBox.value.transcribe(audioArray: silentAudio)
                } catch {
                    logError("WhisperKit warmup failed for \(model.rawValue): \(error)")
                    throw TranscriberError.warmupFailed(
                        model: model.rawValue,
                        backend: model.backend.rawValue,
                        underlying: error
                    )
                }
            }
            logInfo("WhisperKit warmed up and ready")
        } catch let error as TranscriberError {
            throw error
        } catch {
            logError("Failed to initialize WhisperKit: \(error)")
            throw TranscriberError.modelNotFound(model.rawValue)
        }
    }

    private func initializeParakeet(model: TranscriptionModel) async throws {
        guard let version = model.asrModelVersion else {
            throw TranscriberError.modelNotFound(model.rawValue)
        }

        do {
            logInfo("Downloading/loading Parakeet \(version) models...")
            let models = try await AsrModels.downloadAndLoad(version: version)

            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: models)

            // Warmup with silent audio
            logInfo("Warming up Parakeet...")
            let silentAudio = [Float](repeating: 0, count: 16000) // 1 second of silence
            do {
                _ = try await asrManager?.transcribe(silentAudio, source: .microphone)
            } catch {
                logError("Parakeet warmup failed for \(model.rawValue): \(error)")
                throw TranscriberError.warmupFailed(
                    model: model.rawValue,
                    backend: model.backend.rawValue,
                    underlying: error
                )
            }

            logInfo("Parakeet warmed up and ready")
        } catch let error as TranscriberError {
            throw error
        } catch {
            logError("Failed to initialize Parakeet: \(error)")
            throw TranscriberError.modelNotFound(model.rawValue)
        }
    }

    /// Transcribe audio samples to text
    /// - Parameter audioSamples: Audio samples at 16kHz mono
    /// - Returns: Transcribed text
    func transcribe(_ audioSamples: [Float]) async throws -> String {
        guard let model = currentModel else {
            throw TranscriberError.notInitialized
        }

        logInfo("Starting transcription of \(audioSamples.count) samples using \(model.backend.rawValue)")

        do {
            // Try local transcription first
            switch model.backend {
            case .whisper:
                return try await transcribeWithWhisper(audioSamples)
            case .parakeet:
                return try await transcribeWithParakeet(audioSamples)
            }
        } catch {
            // If local fails and cloud fallback is enabled, try cloud
            if cloudFallbackSettings.enabled {
                logWarning("Local transcription failed: \(error.localizedDescription). Trying cloud fallback...")
                return try await transcribeWithCloud(audioSamples)
            }
            throw error
        }
    }

    /// Transcribe using cloud only (useful when local model unavailable)
    func transcribeWithCloud(_ audioSamples: [Float]) async throws -> String {
        var attemptedProvider = false
        var lastError: Error?

        let preferredType = cloudFallbackSettings.preferredProvider

        // Try preferred provider first
        if let entry = cloudProviders.first(where: { $0.type == preferredType }),
           entry.provider.isConfigured
        {
            attemptedProvider = true
            logInfo("Transcribing with cloud provider: \(entry.provider.displayName)")
            do {
                return try await entry.provider.transcribe(audioSamples)
            } catch {
                lastError = error
                logWarning("Preferred cloud provider failed: \(error.localizedDescription)")
            }
        }

        // Try remaining configured providers in order
        for entry in cloudProviders where entry.type != preferredType && entry.provider.isConfigured {
            attemptedProvider = true
            logInfo("Trying fallback cloud provider: \(entry.provider.displayName)")
            do {
                return try await entry.provider.transcribe(audioSamples)
            } catch {
                lastError = error
                logWarning("Fallback cloud provider failed: \(error.localizedDescription)")
            }
        }

        if attemptedProvider, let lastError {
            throw lastError
        }

        throw CloudTranscriptionError.notConfigured
    }

    /// Check if any cloud provider is configured
    var hasCloudProvider: Bool {
        cloudProviders.contains { $0.provider.isConfigured }
    }

    /// Get list of configured cloud providers
    var configuredCloudProviders: [CloudProvider] {
        cloudProviders.filter(\.provider.isConfigured).map(\.provider)
    }

    private func transcribeWithWhisper(_ audioSamples: [Float]) async throws -> String {
        guard let whisperKit else {
            throw TranscriberError.notInitialized
        }

        let kitBox = UncheckedSendableBox(value: whisperKit)
        let startTime = Date()

        let text = try await raceAgainstTimeout {
            // Noise-optimized decode options:
            // - usePrefillPrompt=false prevents hallucination loops from prior context
            // - suppressBlank=true suppresses empty/blank tokens on noise-only segments
            // - compressionRatioThreshold detects repetitive hallucinations
            // - noSpeechThreshold detects silence/noise-only segments
            let options = DecodingOptions(
                usePrefillPrompt: false,
                usePrefillCache: false,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                noSpeechThreshold: 0.6
            )
            let results = try await kitBox.value.transcribe(audioArray: audioSamples, decodeOptions: options)
            return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        let ms = Int(Date().timeIntervalSince(startTime) * 1000)
        logInfo("Whisper transcription complete: \(text.count) chars in \(ms)ms")
        return text
    }

    private func transcribeWithParakeet(_ audioSamples: [Float]) async throws -> String {
        guard let asrManager else {
            throw TranscriberError.notInitialized
        }

        // Parakeet requires at least 1 second of audio (16000 samples at 16kHz)
        guard audioSamples.count >= AppConstants.minTranscriptionSamples else {
            throw TranscriberError.invalidAudioData
        }

        let asrManagerBox = UncheckedSendableBox(value: asrManager)
        let startTime = Date()

        let text = try await raceAgainstTimeout {
            let result = try await asrManagerBox.value.transcribe(audioSamples, source: .microphone)
            return result.text.trimmingCharacters(in: .whitespaces)
        }

        let ms = Int(Date().timeIntervalSince(startTime) * 1000)
        logInfo("Parakeet transcription complete: \(text.count) chars in \(ms)ms")
        return text
    }

    /// Runs a transcription `operation` in a detached task and races it against
    /// the configured timeout. Whichever finishes first wins; the losing task
    /// is cancelled but a stuck inference is left to finish detached so the
    /// caller returns/throws promptly and the timeout actually bounds the wait.
    /// Throws `TranscriberError.timeout` when the timeout wins.
    private func raceAgainstTimeout(
        _ operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let gate = TranscriptionRaceGate()
        let timeout = timeoutSeconds

        let work = Task.detached {
            do {
                await gate.settle(.success(try await operation()))
            } catch {
                await gate.settle(.failure(UncheckedSendableBox(value: error)))
            }
        }
        let timer = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            await gate.settle(.failure(UncheckedSendableBox(value: TranscriberError.timeout)))
        }

        let outcome = await gate.wait()
        // Cancel both; the winner is already done, and a stuck loser detaches.
        timer.cancel()
        work.cancel()

        switch outcome {
        case let .success(text):
            return text
        case let .failure(box):
            throw box.value
        }
    }

    /// Check if transcriber is ready
    var isReady: Bool {
        whisperKit != nil || asrManager?.isAvailable == true
    }

    /// Current model being used
    var model: TranscriptionModel? {
        currentModel
    }
}

// MARK: - Transcription Race Gate

/// First-result-wins outcome for a transcription/timeout race. The error case
/// is boxed so an arbitrary `Error` can cross into the gate actor safely.
private enum TranscriptionOutcome: Sendable {
    case success(String)
    case failure(UncheckedSendableBox<Error>)
}

/// Single-fire gate that records whichever of two racing tasks (inference or
/// timeout) settles first and hands the result to a single waiter. Later
/// settle calls are ignored, so a slow loser can finish detached harmlessly.
private actor TranscriptionRaceGate {
    private var outcome: TranscriptionOutcome?
    private var waiter: CheckedContinuation<TranscriptionOutcome, Never>?

    func settle(_ result: TranscriptionOutcome) {
        guard outcome == nil else { return }
        outcome = result
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: result)
        }
    }

    func wait() async -> TranscriptionOutcome {
        if let outcome {
            return outcome
        }
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}
