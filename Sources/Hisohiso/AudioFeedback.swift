import AppKit

/// Provides audio feedback (click sounds) for recording start/stop
final class AudioFeedback {
    private var startSound: NSSound?
    private var stopSound: NSSound?

    /// Whether audio feedback is enabled
    var isEnabled: Bool = true

    init() {
        // Pre-load system sounds for instant playback
        startSound = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
        stopSound = NSSound(contentsOfFile: "/System/Library/Sounds/Pop.aiff", byReference: true)
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
