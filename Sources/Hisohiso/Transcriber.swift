import Foundation
import WhisperKit
import FluidAudio

// MARK: - Transcription Backend

/// Transcription backend type
enum TranscriptionBackend: String, CaseIterable, Identifiable {
    case whisper = "whisper"
    case parakeet = "parakeet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (WhisperKit)"
        case .parakeet: return "Parakeet (FluidAudio)"
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

    var id: String { rawValue }

    var backend: TranscriptionBackend {
        switch self {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperLargeV3Turbo, .whisperDistilLargeV3:
            return .whisper
        case .parakeetV2, .parakeetV3:
            return .parakeet
        }
    }

    var displayName: String {
        switch self {
        case .whisperTiny: return "Whisper Tiny (~66 MB)"
        case .whisperBase: return "Whisper Base English (~105 MB)"
        case .whisperSmall: return "Whisper Small English (~330 MB)"
        case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo (~954 MB)"
        case .whisperDistilLargeV3: return "Whisper Distil Large V3 (~800 MB)"
        case .parakeetV2: return "Parakeet v2 English (~2.6 GB) ⭐"
        case .parakeetV3: return "Parakeet v3 Multilingual (~2.7 GB)"
        }
    }

    var asrModelVersion: AsrModelVersion? {
        switch self {
        case .parakeetV2: return .v2
        case .parakeetV3: return .v3
        default: return nil
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
    case transcriptionFailed(Error)
    case timeout
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcriber not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .timeout:
            return "Transcription timed out"
        case .invalidAudioData:
            return "Invalid or too short audio data"
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
    static func load() -> CloudFallbackSettings {
        let defaults = UserDefaults.standard
        return CloudFallbackSettings(
            enabled: defaults.bool(forKey: "cloudFallbackEnabled"),
            preferredProvider: CloudProviderType(
                rawValue: defaults.string(forKey: "cloudFallbackProvider") ?? "openai"
            ) ?? .openAI
        )
    }

    /// Save to UserDefaults
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "cloudFallbackEnabled")
        defaults.set(preferredProvider.rawValue, forKey: "cloudFallbackProvider")
    }
}

// MARK: - Transcriber

/// Multi-backend transcription service supporting WhisperKit, FluidAudio (Parakeet), and cloud fallback
actor Transcriber {
    private var whisperKit: WhisperKit?
    private var asrManager: AsrManager?
    private var currentModel: TranscriptionModel?
    private let timeoutSeconds: TimeInterval = 30

    /// Cloud providers for fallback
    private let cloudProviders: [CloudProviderType: CloudProvider] = [
        .openAI: OpenAIProvider(),
        .groq: GroqProvider()
    ]

    /// Cloud fallback settings
    var cloudFallbackSettings = CloudFallbackSettings.load()

    /// Initialize the transcriber with a specific model
    /// - Parameter model: The model to use for transcription
    func initialize(model: TranscriptionModel = .defaultModel) async throws {
        logInfo("Initializing transcriber with model: \(model.rawValue) (backend: \(model.backend.rawValue))")

        // Reset previous state
        whisperKit = nil
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
                logInfo("Warming up WhisperKit...")
                let silentAudio = [Float](repeating: 0, count: 16000) // 1 second of silence
                _ = try? await kit.transcribe(audioArray: silentAudio)
            }
            logInfo("WhisperKit warmed up and ready")
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
            _ = try? await asrManager?.transcribe(silentAudio, source: .microphone)

            logInfo("Parakeet warmed up and ready")
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
    /// - Parameter audioSamples: Audio samples at 16kHz mono
    /// - Returns: Transcribed text
    func transcribeWithCloud(_ audioSamples: [Float]) async throws -> String {
        var attemptedProvider = false
        var lastError: Error?

        // Try preferred provider first
        let preferredType = cloudFallbackSettings.preferredProvider
        if let provider = cloudProviders[preferredType], provider.isConfigured {
            attemptedProvider = true
            logInfo("Transcribing with cloud provider: \(provider.displayName)")
            do {
                return try await provider.transcribe(audioSamples)
            } catch {
                lastError = error
                logWarning("Preferred cloud provider failed: \(error.localizedDescription)")
            }
        }

        // Try other configured providers
        for (type, provider) in cloudProviders where type != preferredType && provider.isConfigured {
            attemptedProvider = true
            logInfo("Trying fallback cloud provider: \(provider.displayName)")
            do {
                return try await provider.transcribe(audioSamples)
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
        cloudProviders.values.contains { $0.isConfigured }
    }

    /// Get list of configured cloud providers
    var configuredCloudProviders: [CloudProvider] {
        cloudProviders.values.filter { $0.isConfigured }
    }

    private func transcribeWithWhisper(_ audioSamples: [Float]) async throws -> String {
        guard let whisperKit else {
            throw TranscriberError.notInitialized
        }

        let kit = whisperKit
        let timeout = timeoutSeconds

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let results = try await kit.transcribe(audioArray: audioSamples)
                return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranscriberError.timeout
            }

            guard let result = try await group.next() else {
                throw TranscriberError.transcriptionFailed(NSError(domain: "Transcriber", code: -1))
            }

            group.cancelAll()
            logInfo("Whisper transcription complete: \(result.prefix(50))...")
            return result
        }
    }

    private func transcribeWithParakeet(_ audioSamples: [Float]) async throws -> String {
        guard let asrManager else {
            throw TranscriberError.notInitialized
        }

        // Parakeet requires at least 1 second of audio (16000 samples at 16kHz)
        guard audioSamples.count >= 16000 else {
            throw TranscriberError.invalidAudioData
        }

        let timeout = timeoutSeconds

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let result = try await asrManager.transcribe(audioSamples, source: .microphone)
                return result.text.trimmingCharacters(in: .whitespaces)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranscriberError.timeout
            }

            guard let result = try await group.next() else {
                throw TranscriberError.transcriptionFailed(NSError(domain: "Transcriber", code: -1))
            }

            group.cancelAll()
            logInfo("Parakeet transcription complete: \(result.prefix(50))...")
            return result
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
