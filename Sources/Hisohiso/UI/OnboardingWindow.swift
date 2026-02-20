import Cocoa
import AVFoundation
import ServiceManagement

/// Onboarding window shown on first launch
final class OnboardingWindow: NSWindow {
    private var onComplete: () -> Void
    private var accessibilityCheck: NSButton!
    private var microphoneCheck: NSButton!
    private var launchToggle: NSButton!
    private var continueButton: NSButton!
    private var refreshTimer: Timer?
    private let supportsLaunchAtLogin = Bundle.main.bundleURL.pathExtension == "app"

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Welcome to Hisohiso"
        isReleasedWhenClosed = false
        center()
        
        setupContent()
        startPermissionMonitoring()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    private func setupContent() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 340))
        
        // Icon
        let icon = NSImageView(frame: NSRect(x: 170, y: 270, width: 80, height: 50))
        if let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            icon.image = img.withSymbolConfiguration(config)
            icon.contentTintColor = .controlAccentColor
        }
        contentView.addSubview(icon)
        
        // Title
        let title = NSTextField(labelWithString: "Hisohiso")
        title.font = .boldSystemFont(ofSize: 24)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 235, width: 420, height: 30)
        contentView.addSubview(title)
        
        // Subtitle
        let subtitle = NSTextField(labelWithString: "Local AI dictation with the Globe key")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 0, y: 210, width: 420, height: 20)
        contentView.addSubview(subtitle)
        
        // Divider
        let divider = NSBox(frame: NSRect(x: 20, y: 195, width: 380, height: 1))
        divider.boxType = .separator
        contentView.addSubview(divider)
        
        // Checklist header
        let header = NSTextField(labelWithString: "Setup Checklist")
        header.font = .boldSystemFont(ofSize: 14)
        header.frame = NSRect(x: 30, y: 160, width: 200, height: 20)
        contentView.addSubview(header)
        
        // Accessibility row
        accessibilityCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        accessibilityCheck.frame = NSRect(x: 30, y: 125, width: 20, height: 20)
        accessibilityCheck.isEnabled = false
        contentView.addSubview(accessibilityCheck)
        
        let accLabel = NSTextField(labelWithString: "Accessibility Permission")
        accLabel.font = .systemFont(ofSize: 13)
        accLabel.frame = NSRect(x: 55, y: 125, width: 200, height: 18)
        contentView.addSubview(accLabel)
        
        let accButton = NSButton(title: "Grant", target: self, action: #selector(openAccessibility))
        accButton.bezelStyle = .rounded
        accButton.controlSize = .small
        accButton.frame = NSRect(x: 330, y: 122, width: 60, height: 24)
        contentView.addSubview(accButton)
        
        // Microphone row
        microphoneCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        microphoneCheck.frame = NSRect(x: 30, y: 90, width: 20, height: 20)
        microphoneCheck.isEnabled = false
        contentView.addSubview(microphoneCheck)
        
        let micLabel = NSTextField(labelWithString: "Microphone Permission")
        micLabel.font = .systemFont(ofSize: 13)
        micLabel.frame = NSRect(x: 55, y: 90, width: 200, height: 18)
        contentView.addSubview(micLabel)
        
        let micButton = NSButton(title: "Grant", target: self, action: #selector(openMicrophone))
        micButton.bezelStyle = .rounded
        micButton.controlSize = .small
        micButton.frame = NSRect(x: 330, y: 87, width: 60, height: 24)
        contentView.addSubview(micButton)
        
        // Launch at login
        let launchTitle = supportsLaunchAtLogin
            ? "Launch at Login"
            : "Launch at Login (app bundle only)"
        launchToggle = NSButton(checkboxWithTitle: launchTitle, target: nil, action: nil)
        launchToggle.state = supportsLaunchAtLogin ? .on : .off
        launchToggle.isEnabled = supportsLaunchAtLogin
        launchToggle.frame = NSRect(x: 30, y: 50, width: 320, height: 20)
        contentView.addSubview(launchToggle)
        
        // Continue button
        continueButton = NSButton(title: "Get Started", target: self, action: #selector(finishOnboarding))
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.frame = NSRect(x: 130, y: 10, width: 160, height: 32)
        continueButton.keyEquivalent = "\r"
        contentView.addSubview(continueButton)
        
        self.contentView = contentView
        updatePermissionStatus()
    }
    
    private func startPermissionMonitoring() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
    }
    
    private func updatePermissionStatus() {
        let hasAccessibility = AXIsProcessTrusted()
        accessibilityCheck.state = hasAccessibility ? .on : .off
        
        let hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        microphoneCheck.state = hasMicrophone ? .on : .off
        
        continueButton.isEnabled = hasAccessibility && hasMicrophone
    }
    
    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePermissionStatus()
            }
        }
    }
    
    @objc private func finishOnboarding() {
        refreshTimer?.invalidate()

        if supportsLaunchAtLogin && launchToggle.state == .on {
            do {
                try SMAppService.mainApp.register()
            } catch {
                logError("Failed to enable launch at login during onboarding: \(error)")
            }
        }

        close()
        onComplete()
    }
}
