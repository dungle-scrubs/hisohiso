@preconcurrency import ApplicationServices
import Cocoa
import CoreGraphics

/// Monitors the Globe/Fn key using the shared EventTapManager and NSEvent fallback.
///
/// The Globe key on macOS is detected via `.maskSecondaryFn` flag (0x800000) in CGEventFlags.
/// We also use NSEvent.addGlobalMonitorForEvents as a backup.
/// Tap versus hold is decided by `PressGestureDetector`, shared with `HotkeyManager`.
/// Requires Accessibility permission to function.
@MainActor
final class GlobeKeyMonitor {
    private static let registrationID = "globe-key-monitor"

    private var nsEventMonitor: Any?
    private let gesture = PressGestureDetector()

    /// Called when Globe key is tapped (quick press and release)
    var onGlobeTap: (@MainActor () -> Void)? {
        get { gesture.onTap }
        set { gesture.onTap = newValue }
    }

    /// Called when Globe key is held down (long press)
    var onGlobeHoldStart: (@MainActor () -> Void)? {
        get { gesture.onHoldStart }
        set { gesture.onHoldStart = newValue }
    }

    /// Called when Globe key is released after being held
    var onGlobeHoldEnd: (@MainActor () -> Void)? {
        get { gesture.onHoldEnd }
        set { gesture.onHoldEnd = newValue }
    }

    deinit {
        MainActor.assumeIsolated {
            EventTapManager.shared.unregister(id: Self.registrationID)
            if let monitor = nsEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
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
        gesture.reset()
        logInfo("GlobeKeyMonitor stopped")
    }

    private func handleGlobeState(pressed: Bool, source: String) {
        if pressed, !gesture.isPressed {
            logDebug("Globe key down (via \(source))")
            gesture.press()
        } else if !pressed, gesture.isPressed {
            logDebug("Globe key up (via \(source))")
            gesture.release()
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
