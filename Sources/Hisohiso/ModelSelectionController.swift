import Foundation

@MainActor
protocol ModelReloading: AnyObject {
    var isModelReloadAllowed: Bool { get }
    func reloadSelectedModel() async throws
}

/// Owns model selection persistence and runtime reload policy.
@MainActor
final class ModelSelectionController {
    enum ReloadPolicy {
        case deferUntilIdle
        case immediately
        case persistOnly
    }

    private let modelManager: ModelManager
    private weak var reloader: (any ModelReloading)?
    private(set) var hasPendingReload = false

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    var selectedModel: TranscriptionModel {
        modelManager.selectedModel
    }

    func attachReloader(_ reloader: any ModelReloading) {
        self.reloader = reloader
    }

    func requestSelection(
        _ model: TranscriptionModel,
        reloadPolicy: ReloadPolicy = .deferUntilIdle
    ) async throws {
        modelManager.selectedModel = model
        modelManager.saveSelectedModel()

        switch reloadPolicy {
        case .persistOnly:
            return
        case .immediately:
            try await reloadNow()
        case .deferUntilIdle:
            do {
                try await reloadNow()
            } catch let dictationError as DictationError where dictationError == .cannotChangeModelWhileBusy {
                hasPendingReload = true
                logWarning("Model change queued until dictation returns to idle")
            }
        }
    }

    func applyPendingReloadIfPossible() async {
        guard hasPendingReload else { return }
        do {
            try await reloadNow()
            logInfo("Applied pending model change")
        } catch let dictationError as DictationError where dictationError == .cannotChangeModelWhileBusy {
            hasPendingReload = true
        } catch {
            logError("Failed to apply pending model change: \(error)")
        }
    }

    private func reloadNow() async throws {
        guard let reloader else { return }
        guard reloader.isModelReloadAllowed else {
            throw DictationError.cannotChangeModelWhileBusy
        }
        try await reloader.reloadSelectedModel()
        hasPendingReload = false
    }
}
