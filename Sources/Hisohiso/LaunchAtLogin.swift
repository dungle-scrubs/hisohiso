import Foundation
import ServiceManagement

/// Manages launch at login setting using SMAppService
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                updateLaunchAtLogin()
            }
        }
    }

    init() {
        // Check current status
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
                logInfo("Launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                logInfo("Launch at login disabled")
            }
        } catch {
            logError("Failed to update launch at login: \(error)")
            // Revert the change
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
