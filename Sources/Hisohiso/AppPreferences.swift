import Foundation

/// Typed facade for persisted app preferences and related secure settings.
///
/// UI code should call this facade instead of coordinating `UserDefaults`,
/// Keychain, and notification side effects directly.
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let keychain: KeychainManager
    private let notificationCenter: NotificationCenter

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainManager = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.notificationCenter = notificationCenter
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(for: .hasCompletedOnboarding) }
        set { defaults.set(newValue, for: .hasCompletedOnboarding) }
    }

    var audioFeedbackEnabled: Bool {
        get {
            defaults.hasValue(for: .audioFeedbackEnabled)
                ? defaults.bool(for: .audioFeedbackEnabled)
                : true
        }
        set { defaults.set(newValue, for: .audioFeedbackEnabled) }
    }

    var useAudioKit: Bool {
        get { defaults.bool(for: .useAudioKit) }
        set { defaults.set(newValue, for: .useAudioKit) }
    }

    /// Whether to show the floating pill recording indicator.
    var showFloatingPill: Bool {
        get { defaults.bool(for: .showFloatingPill) }
        set { defaults.set(newValue, for: .showFloatingPill) }
    }

    var selectedAudioDeviceUID: String? {
        defaults.string(for: .selectedAudioDeviceUID)
    }

    func selectAudioDevice(_ device: AudioInputDevice) {
        if device == .systemDefault {
            defaults.remove(for: .selectedAudioDeviceUID)
        } else {
            defaults.set(device.uid, for: .selectedAudioDeviceUID)
        }
        notificationCenter.post(name: .audioInputDeviceChanged, object: nil)
    }

    var wakeWordEnabled: Bool {
        get { defaults.bool(for: .wakeWordEnabled) }
        set {
            defaults.set(newValue, for: .wakeWordEnabled)
            notificationCenter.post(name: .wakeWordSettingsChanged, object: nil)
        }
    }

    var wakePhrase: String {
        get { defaults.string(for: .wakePhrase) ?? AppConstants.defaultWakePhrase }
        set {
            defaults.set(newValue.lowercased().trimmingCharacters(in: .whitespaces), for: .wakePhrase)
            notificationCenter.post(name: .wakeWordSettingsChanged, object: nil)
        }
    }

    var fillerWords: [String] {
        get { defaults.stringArray(for: .fillerWords) ?? Array(TextFormatter.defaultFillerWords) }
        set { defaults.set(newValue, forKey: SettingsKey.fillerWords.rawValue) }
    }

    var cloudFallbackSettings: CloudFallbackSettings {
        get { CloudFallbackSettings.load(defaults: defaults) }
        set { newValue.save(defaults: defaults) }
    }

    func hasAPIKey(_ type: KeychainManager.APIKeyType) -> Bool {
        keychain.hasAPIKey(type)
    }

    func setAPIKey(_ key: String, type: KeychainManager.APIKeyType) {
        if key.isEmpty {
            _ = keychain.deleteAPIKey(type)
        } else {
            _ = keychain.setAPIKey(key, type: type)
        }
    }
}
