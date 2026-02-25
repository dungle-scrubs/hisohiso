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
    private var enrollmentSamples: [[Float]] = []
    private var isRecordingEnrollment = false
    private var enrollmentRecorder: AudioRecorder?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
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
        isRecordingEnrollment = false
        enrollmentRecorder?.cancelRecording()
        enrollmentRecorder = nil
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
        if isRecordingEnrollment { stopEnrollmentRecording() }
        else { beginEnrollment() }
    }

    private func beginEnrollment() {
        enrollmentSamples = []
        isRecordingEnrollment = true
        enrollmentRecorder = AudioRecorder()
        enrollButton.title = "Stop Recording"
        clearButton.isEnabled = false
        progressLabel.stringValue = "🎤 Speak naturally for 5-10 seconds... (0 samples)"
        progressLabel.textColor = .systemRed
        collectEnrollmentSample()
    }

    private func collectEnrollmentSample() {
        guard isRecordingEnrollment, let recorder = enrollmentRecorder else { return }
        do {
            try recorder.startRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, isRecordingEnrollment else { return }
                let samples = recorder.stopRecording()
                if samples.count >= VoiceVerifier.minSamplesForVerification {
                    enrollmentSamples.append(samples)
                    progressLabel.stringValue = "🎤 Keep speaking... (\(enrollmentSamples.count) samples)"
                }
                if enrollmentSamples.count < 3 { collectEnrollmentSample() }
                else { stopEnrollmentRecording() }
            }
        } catch {
            logError("Failed to start enrollment recording: \(error)")
            progressLabel.stringValue = "✗ Failed to access microphone"
            progressLabel.textColor = .systemRed
            isRecordingEnrollment = false
            enrollmentRecorder = nil
            enrollButton.title = "Start Enrollment"
        }
    }

    private func stopEnrollmentRecording() {
        isRecordingEnrollment = false
        enrollmentRecorder = nil
        enrollButton.title = "Processing..."
        enrollButton.isEnabled = false
        guard !enrollmentSamples.isEmpty else {
            progressLabel.stringValue = "✗ No audio captured"
            progressLabel.textColor = .systemRed
            enrollButton.title = "Start Enrollment"
            enrollButton.isEnabled = true
            return
        }
        Task { @MainActor in
            do {
                try await VoiceVerifier.shared.enroll(with: enrollmentSamples)
                progressLabel.stringValue = "✓ Enrollment complete!"
                progressLabel.textColor = .systemGreen
            } catch {
                progressLabel.stringValue = "✗ \(error.localizedDescription)"
                progressLabel.textColor = .systemRed
                logError("Enrollment failed: \(error)")
            }
            enrollButton.isEnabled = true
            updateVoiceStatus()
        }
    }

    @objc private func clearEnrollment() {
        VoiceVerifier.shared.clearEnrollment()
        progressLabel.stringValue = ""
        updateVoiceStatus()
    }
}
