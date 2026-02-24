import Foundation
import WhisperKit
import FluidAudio

/// Manages model downloads and storage for both WhisperKit and FluidAudio
@MainActor
final class ModelManager: ObservableObject {
    /// Storage directory for WhisperKit models
    static let whisperModelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Hisohiso/Models/Whisper", isDirectory: true)
    }()

    /// Storage directory for FluidAudio models (Parakeet)
    static let fluidAudioModelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Hisohiso/Models/FluidAudio", isDirectory: true)
    }()

    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadedModels: Set<TranscriptionModel> = []
    @Published var selectedModel: TranscriptionModel = .defaultModel

    init() {
        // Load saved model selection
        if let savedModel = UserDefaults.standard.string(for: .selectedModel),
           let model = TranscriptionModel(rawValue: savedModel) {
            selectedModel = model
        }

        Task {
            await refreshDownloadedModels()
        }
    }

    /// Check which models are already downloaded
    func refreshDownloadedModels() async {
        var downloaded: Set<TranscriptionModel> = []

        for model in TranscriptionModel.allCases {
            if await isModelDownloaded(model) {
                downloaded.insert(model)
            }
        }

        downloadedModels = downloaded
        logInfo("Downloaded models: \(downloaded.map(\.rawValue))")
    }

    /// Check if a specific model is downloaded
    /// - Parameter model: Model to check
    /// - Returns: true if model files exist
    func isModelDownloaded(_ model: TranscriptionModel) async -> Bool {
        switch model.backend {
        case .whisper:
            let modelPath = Self.whisperModelsDirectory.appendingPathComponent(model.rawValue)
            return FileManager.default.fileExists(atPath: modelPath.path)

        case .parakeet:
            // FluidAudio stores models in its own cache directory
            // Use AsrModels.modelsExist to check if all required files are present
            guard let version = model.asrModelVersion else { return false }
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            return AsrModels.modelsExist(at: cacheDir, version: version)
        }
    }

    /// Download a model
    /// - Parameter model: Model to download
    func downloadModel(_ model: TranscriptionModel) async throws {
        guard !isDownloading else {
            logWarning("Download already in progress")
            return
        }

        isDownloading = true
        downloadProgress = 0
        defer {
            isDownloading = false
            downloadProgress = 0
        }

        logInfo("Starting download of model: \(model.rawValue)")

        do {
            switch model.backend {
            case .whisper:
                try await downloadWhisperModel(model)
            case .parakeet:
                try await downloadParakeetModel(model)
            }

            await refreshDownloadedModels()
        } catch {
            logError("Model download failed: \(error)")
            throw error
        }
    }

    private func downloadWhisperModel(_ model: TranscriptionModel) async throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: Self.whisperModelsDirectory,
            withIntermediateDirectories: true
        )

        // Download using WhisperKit's built-in download
        let modelPath = try await WhisperKit.download(
            variant: model.rawValue,
            downloadBase: Self.whisperModelsDirectory,
            useBackgroundSession: false
        ) { progress in
            Task { @MainActor in
                self.downloadProgress = progress.fractionCompleted
            }
        }

        logInfo("Whisper model downloaded to: \(modelPath)")
    }

    private func downloadParakeetModel(_ model: TranscriptionModel) async throws {
        guard let version = model.asrModelVersion else {
            throw NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid model version"])
        }

        logInfo("Downloading Parakeet \(version) models via FluidAudio...")

        // FluidAudio doesn't expose download progress. Use an indeterminate
        // animation by cycling downloadProgress while waiting.
        let progressTask = Task { @MainActor in
            var tick: Double = 0
            while !Task.isCancelled {
                // Oscillate between 0.05 and 0.95 to signal "working"
                tick += 0.02
                downloadProgress = 0.05 + 0.9 * abs(sin(tick))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        defer { progressTask.cancel() }

        _ = try await AsrModels.downloadAndLoad(version: version)

        logInfo("Parakeet \(version) models downloaded")
        downloadProgress = 1.0
    }

    /// Delete a downloaded model
    /// - Parameter model: Model to delete
    func deleteModel(_ model: TranscriptionModel) throws {
        switch model.backend {
        case .whisper:
            let modelPath = Self.whisperModelsDirectory.appendingPathComponent(model.rawValue)
            guard FileManager.default.fileExists(atPath: modelPath.path) else { return }
            try FileManager.default.removeItem(at: modelPath)

        case .parakeet:
            guard let version = model.asrModelVersion else { return }
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            guard FileManager.default.fileExists(atPath: cacheDir.path) else { return }
            try FileManager.default.removeItem(at: cacheDir)
        }

        downloadedModels.remove(model)
        logInfo("Deleted model: \(model.rawValue)")
    }

    /// Get the path for a downloaded model (Whisper only)
    /// - Parameter model: Model to get path for
    /// - Returns: Path to model directory if it exists
    func modelPath(_ model: TranscriptionModel) -> String? {
        guard model.backend == .whisper else { return nil }
        let path = Self.whisperModelsDirectory.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: path.path) ? path.path : nil
    }

    /// Save the selected model to UserDefaults
    func saveSelectedModel() {
        UserDefaults.standard.set(selectedModel.rawValue, for: .selectedModel)
        logInfo("Saved selected model: \(selectedModel.rawValue)")
    }
}
