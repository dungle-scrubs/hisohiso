import Foundation

/// Centralized notification names used across the app.
///
/// Previously scattered in `PreferencesWindow.swift`.
extension Notification.Name {
    /// Posted when the user selects a different transcription model.
    static let modelSelectionChanged = Notification.Name("modelSelectionChanged")

    /// Posted when the user changes the audio input device.
    static let audioInputDeviceChanged = Notification.Name("audioInputDeviceChanged")

    /// Posted when wake word settings (enabled state or phrase) change.
    static let wakeWordSettingsChanged = Notification.Name("wakeWordSettingsChanged")
}
