import Foundation
import WhisperKit

/// Manages WhisperKit model downloads and storage
@MainActor
final class ModelManager: ObservableObject {
    /// Storage directory for models
    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Hisohiso/Models", isDirectory: true)
    }()

    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadedModels: Set<TranscriptionModel> = []
    @Published var selectedModel: TranscriptionModel = .defaultModel

    init() {
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
        let modelPath = Self.modelsDirectory.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: modelPath.path)
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

        logInfo("Starting download of model: \(model.rawValue)")

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: Self.modelsDirectory,
                withIntermediateDirectories: true
            )

            // Download using WhisperKit's built-in download
            let modelPath = try await WhisperKit.download(
                variant: model.rawValue,
                downloadBase: Self.modelsDirectory,
                useBackgroundSession: false
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                }
            }

            logInfo("Model downloaded to: \(modelPath)")

            await refreshDownloadedModels()
        } catch {
            logError("Model download failed: \(error)")
            throw error
        }

        isDownloading = false
        downloadProgress = 0
    }

    /// Delete a downloaded model
    /// - Parameter model: Model to delete
    func deleteModel(_ model: TranscriptionModel) throws {
        let modelPath = Self.modelsDirectory.appendingPathComponent(model.rawValue)

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return
        }

        try FileManager.default.removeItem(at: modelPath)
        downloadedModels.remove(model)
        logInfo("Deleted model: \(model.rawValue)")
    }

    /// Get the path for a downloaded model
    /// - Parameter model: Model to get path for
    /// - Returns: Path to model directory if it exists
    func modelPath(_ model: TranscriptionModel) -> String? {
        let path = Self.modelsDirectory.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: path.path) ? path.path : nil
    }
}
