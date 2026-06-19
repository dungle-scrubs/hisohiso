import Cocoa

/// Voice preferences tab: voice verification toggle, threshold, enrollment.
final class VoicePreferencesTab: NSView {
    private var verificationToggle: NSButton!
    private var thresholdSlider: NSSlider!
    private var thresholdLabel: NSTextField!
    private var enrollButton: NSButton!
    private var clearButton: NSButton!
    private var statusLabel: NSTextField!
    private var progressLabel: NSTextField!
    private let enrollmentController: VoiceEnrollmentController

    override init(frame frameRect: NSRect) {
        enrollmentController = VoiceEnrollmentController(
            verifier: VoiceVerifier.shared,
            recorderFactory: {
                if AppPreferences.shared.useAudioKit {
                    return AudioKitRecorder()
                }
                return AudioRecorder()
            },
            sampleDuration: 2.5,
            debugLogging: false
        )
        super.init(frame: frameRect)
        setupViews()
        setupEnrollmentController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        var y = 260

        verificationToggle = NSButton(
            checkboxWithTitle: "Enable voice verification",
            target: self,
            action: #selector(verificationChanged)
        )
        verificationToggle.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        addSubview(verificationToggle)

        let desc = NSTextField(labelWithString: "Only transcribe when your voice is detected")
        desc.frame = NSRect(x: 40, y: y - 18, width: 380, height: 16)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .tertiaryLabelColor
        addSubview(desc)
        y -= 45

        let sensitivityLabel = NSTextField(labelWithString: "Sensitivity:")
        sensitivityLabel.frame = NSRect(x: 20, y: y, width: 80, height: 20)
        addSubview(sensitivityLabel)

        thresholdSlider = NSSlider(
            value: 50,
            minValue: 0,
            maxValue: 100,
            target: self,
            action: #selector(thresholdChanged)
        )
        thresholdSlider.frame = NSRect(x: 110, y: y, width: 200, height: 20)
        addSubview(thresholdSlider)

        thresholdLabel = NSTextField(labelWithString: "50%")
        thresholdLabel.frame = NSRect(x: 320, y: y, width: 50, height: 20)
        thresholdLabel.alignment = .right
        addSubview(thresholdLabel)
        y -= 35

        let separator = NSBox(frame: NSRect(x: 20, y: y, width: 420, height: 1))
        separator.boxType = .separator
        addSubview(separator)
        y -= 25

        let enrollHeader = NSTextField(labelWithString: "Voice Enrollment")
        enrollHeader.font = .boldSystemFont(ofSize: 12)
        enrollHeader.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        addSubview(enrollHeader)
        y -= 25

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        statusLabel.font = .systemFont(ofSize: 12)
        addSubview(statusLabel)
        y -= 28

        enrollButton = NSButton(title: "Start Enrollment", target: self, action: #selector(startEnrollment))
        enrollButton.bezelStyle = .rounded
        enrollButton.frame = NSRect(x: 20, y: y, width: 130, height: 25)
        addSubview(enrollButton)

        clearButton = NSButton(title: "Clear", target: self, action: #selector(clearEnrollment))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 160, y: y, width: 80, height: 25)
        addSubview(clearButton)
        y -= 28

        progressLabel = NSTextField(labelWithString: "Speak naturally for 5-10 seconds to enroll your voice")
        progressLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        addSubview(progressLabel)
    }

    /// Load current settings into controls.
    func loadSettings() {
        verificationToggle.state = VoiceVerifier.shared.isEnabled ? .on : .off
        let displayValue = (VoiceVerifier.shared.threshold - 0.5) / 0.45 * 100
        thresholdSlider.floatValue = displayValue
        updateThresholdLabel()
        updateVoiceStatus()
    }

    /// Cancel any in-progress enrollment (called when window closes).
    func cancelEnrollment() {
        enrollmentController.cancel()
    }

    // MARK: - Helpers

    private func updateThresholdLabel() {
        thresholdLabel.stringValue = "\(Int(thresholdSlider.floatValue))%"
    }

    private func updateVoiceStatus() {
        if VoiceVerifier.shared.isEnrolled {
            statusLabel.stringValue = "✓ Voice enrolled"
            statusLabel.textColor = .systemGreen
            enrollButton.title = "Re-enroll"
            clearButton.isEnabled = true
        } else {
            statusLabel.stringValue = "No voice enrolled"
            statusLabel.textColor = .secondaryLabelColor
            enrollButton.title = "Start Enrollment"
            clearButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func verificationChanged() {
        VoiceVerifier.shared.isEnabled = verificationToggle.state == .on
    }

    @objc private func thresholdChanged() {
        let internalValue = 0.5 + (thresholdSlider.floatValue / 100) * 0.45
        VoiceVerifier.shared.threshold = internalValue
        updateThresholdLabel()
    }

    @objc private func startEnrollment() {
        if case .recording = enrollmentController.status {
            stopEnrollmentRecording()
        } else {
            beginEnrollment()
        }
    }

    private func beginEnrollment() {
        enrollButton.title = "Stop Recording"
        clearButton.isEnabled = false
        enrollmentController.start()
    }

    private func stopEnrollmentRecording() {
        enrollButton.title = "Processing..."
        enrollButton.isEnabled = false
        enrollmentController.stop()
    }

    @objc private func clearEnrollment() {
        VoiceVerifier.shared.clearEnrollment()
        progressLabel.stringValue = ""
        updateVoiceStatus()
    }

    private func setupEnrollmentController() {
        enrollmentController.onStatusChange = { [weak self] status in
            guard let self else { return }

            switch status {
            case .idle:
                break
            case let .recording(sampleCount):
                progressLabel.textColor = .systemRed
                progressLabel.stringValue = sampleCount == 0
                    ? "🎤 Speak naturally for 5-10 seconds... (0 samples)"
                    : "🎤 Keep speaking... (\(sampleCount) samples)"
            case .processing:
                progressLabel.stringValue = "Processing..."
                progressLabel.textColor = .secondaryLabelColor
            case .completed:
                progressLabel.stringValue = "✓ Enrollment complete!"
                progressLabel.textColor = .systemGreen
                enrollButton.title = "Start Enrollment"
                enrollButton.isEnabled = true
                updateVoiceStatus()
            case let .failed(reason):
                progressLabel.stringValue = "✗ \(reason.displayMessage)"
                progressLabel.textColor = .systemRed
                enrollButton.title = "Start Enrollment"
                enrollButton.isEnabled = true
                updateVoiceStatus()
            }
        }
    }
}

private extension VoiceEnrollmentController.FailureReason {
    var displayMessage: String {
        switch self {
        case .noAudioCaptured:
            "No audio captured"
        case .microphoneUnavailable:
            "Failed to access microphone"
        case let .enrollmentFailed(message):
            message
        }
    }
}
