import AppKit

/// Provides audio feedback (click sounds) for recording start/stop
final class AudioFeedback {
    private var startSound: NSSound?
    private var stopSound: NSSound?

    /// Whether audio feedback is enabled (reads from UserDefaults)
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "audioFeedbackEnabled") as? Bool ?? true
    }

    init() {
        // Use named sounds to survive system sound path changes across macOS versions.
        // Falls back to nil (silent) if the sound name is unavailable.
        startSound = NSSound(named: "Tink")
        stopSound = NSSound(named: "Pop")
    }

    /// Play the start recording sound
    func playStart() {
        guard isEnabled else { return }
        startSound?.play()
    }

    /// Play the stop recording sound
    func playStop() {
        guard isEnabled else { return }
        stopSound?.play()
    }
}
