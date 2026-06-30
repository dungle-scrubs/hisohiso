import Foundation
import ServiceManagement

/// Single source of truth for "launch Hisohiso at login".
///
/// Two independent mechanisms can start the app at login:
///
/// - The user **LaunchAgent** (`~/Library/LaunchAgents/com.hisohiso.app.plist`,
///   installed via `make install-agent`), which also provides crash-restart via
///   `KeepAlive`.
/// - The **SMAppService login item** registered with `SMAppService.mainApp`.
///
/// If both are active the app launches twice at login, producing two menu-bar
/// instances that each capture audio and transcribe - so every utterance is
/// transcribed twice. The LaunchAgent is strictly more capable (it restarts the
/// app on crash), so whenever it is installed it owns launch-at-login and the
/// SMAppService item must stay unregistered.
enum LaunchAtLoginManager {
    static let bundleIdentifier = "com.hisohiso.app"

    /// Location of the user LaunchAgent plist.
    static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleIdentifier).plist")
    }

    /// `true` when the user LaunchAgent is installed and therefore owns startup.
    static var launchAgentInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    /// SMAppService only works for a real `.app` bundle, not a bare SwiftPM binary.
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// `true` when launch-at-login is active through either mechanism.
    static var isEnabled: Bool {
        if launchAgentInstalled { return true }
        return isAppBundle && SMAppService.mainApp.status == .enabled
    }

    /// Enable or disable launch-at-login via the SMAppService login item.
    ///
    /// No-op when the LaunchAgent owns startup: the agent already launches the
    /// app, so registering SMAppService here would add a second launcher and
    /// produce a duplicate instance at login.
    /// - Returns: the resulting enabled state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        guard !launchAgentInstalled else { return true }
        guard isAppBundle else { return false }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return SMAppService.mainApp.status == .enabled
    }

    /// Collapse to a single autostart mechanism.
    ///
    /// When the LaunchAgent is installed it is the sole owner of launch-at-login;
    /// a registered SMAppService item would launch a second copy at login, so
    /// unregister it. Safe to call on every launch.
    static func reconcile() {
        guard isAppBundle, launchAgentInstalled, SMAppService.mainApp.status == .enabled else { return }
        do {
            try SMAppService.mainApp.unregister()
            logInfo("Removed redundant SMAppService login item; LaunchAgent owns launch-at-login")
        } catch {
            logError("Failed to remove redundant SMAppService login item: \(error.localizedDescription)")
        }
    }
}
