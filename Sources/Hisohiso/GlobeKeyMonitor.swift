import Cocoa
import CoreGraphics

/// Monitors the Globe/Fn key using the shared EventTapManager and NSEvent fallback.
///
/// The Globe key on macOS is detected via `.maskSecondaryFn` flag (0x800000) in CGEventFlags.
/// We also use NSEvent.addGlobalMonitorForEvents as a backup.
/// Requires Accessibility permission to function.
@MainActor
final class GlobeKeyMonitor {
    private static let registrationID = "globe-key-monitor"

    private var nsEventMonitor: Any?
    private var isGlobePressed = false

    /// Called when Globe key is tapped (quick press and release)
    var onGlobeTap: (@MainActor () -> Void)?

    /// Called when Globe key is held down (long press)
    var onGlobeHoldStart: (@MainActor () -> Void)?

    /// Called when Globe key is released after being held
    var onGlobeHoldEnd: (@MainActor () -> Void)?

    /// Threshold to distinguish tap from hold (in seconds)
    private let holdThreshold: TimeInterval = AppConstants.globeHoldThreshold
    private var pressTime: Date?
    private var isHolding = false

    deinit {
        EventTapManager.shared.unregister(id: Self.registrationID)
        if let monitor = nsEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Start monitoring Globe key events
    /// - Returns: true if monitoring started successfully
    @discardableResult
    func start() -> Bool {
        // Register with the shared event tap for flagsChanged events
        EventTapManager.shared.register(
            id: Self.registrationID,
            eventTypes: [.flagsChanged]
        ) { [weak self] event, _ in
            guard let self else { return false }
            let globePressed = event.flags.contains(.maskSecondaryFn)
            Task { @MainActor [weak self] in
                self?.handleGlobeState(pressed: globePressed, source: "CGEvent")
            }
            return false // Don't consume flagsChanged events
        }

        // Start the shared tap (no-op if already running)
        guard EventTapManager.shared.start() else {
            logError("GlobeKeyMonitor: failed to start event tap. Is Accessibility permission granted?")
            return false
        }

        // NSEvent monitor as backup
        nsEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let globePressed = event.modifierFlags.contains(.function)
            Task { @MainActor [weak self] in
                self?.handleGlobeState(pressed: globePressed, source: "NSEvent")
            }
        }

        logInfo("GlobeKeyMonitor started (EventTapManager + NSEvent)")
        return true
    }

    /// Stop monitoring Globe key events
    func stop() {
        EventTapManager.shared.unregister(id: Self.registrationID)
        if let monitor = nsEventMonitor {
            NSEvent.removeMonitor(monitor)
            nsEventMonitor = nil
        }
        logInfo("GlobeKeyMonitor stopped")
    }

    private func handleGlobeState(pressed: Bool, source: String) {
        if pressed, !isGlobePressed {
            isGlobePressed = true
            pressTime = Date()
            isHolding = false
            logDebug("Globe key down (via \(source))")

            // Schedule hold detection
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, isGlobePressed, !self.isHolding else { return }
                isHolding = true
                logInfo("Globe key hold started")
                onGlobeHoldStart?()
            }
        } else if !pressed, isGlobePressed {
            isGlobePressed = false
            let pressDuration = pressTime.map { Date().timeIntervalSince($0) } ?? 0

            if isHolding {
                logInfo("Globe key hold ended (held \(String(format: "%.2f", pressDuration))s)")
                isHolding = false
                onGlobeHoldEnd?()
            } else {
                logInfo("Globe key tapped (via \(source))")
                onGlobeTap?()
            }
            pressTime = nil
        }
    }

    /// Check if Accessibility permission is granted
    nonisolated static func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let trusted = AXIsProcessTrusted()
        logDebug("AXIsProcessTrusted() = \(trusted)")

        if !trusted, prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        return trusted
    }
}
