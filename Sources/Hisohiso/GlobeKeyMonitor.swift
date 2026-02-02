import Cocoa
import CoreGraphics

/// Monitors the Globe/Fn key using both CGEventTap and NSEvent
///
/// The Globe key on macOS is detected via `.maskSecondaryFn` flag (0x800000) in CGEventFlags.
/// We also use NSEvent.addGlobalMonitorForEvents as a backup.
/// Requires Accessibility permission to function.
@MainActor
final class GlobeKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var nsEventMonitor: Any?
    private var isGlobePressed = false

    /// Called when Globe key is tapped (quick press and release)
    var onGlobeTap: (@MainActor () -> Void)?
    
    /// Called when Globe key is held down (long press)
    var onGlobeHoldStart: (@MainActor () -> Void)?
    
    /// Called when Globe key is released after being held
    var onGlobeHoldEnd: (@MainActor () -> Void)?
    
    /// Threshold to distinguish tap from hold (in seconds)
    private let holdThreshold: TimeInterval = 0.3
    private var pressTime: Date?
    private var isHolding = false

    deinit {
        // Cleanup event tap directly in deinit since stop() is MainActor-isolated
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    /// Start monitoring Globe key events
    /// - Returns: true if monitoring started successfully
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            logWarning("GlobeKeyMonitor already running")
            return true
        }

        // Method 1: CGEventTap
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleFlagsChangedCG(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logError("Failed to create event tap. Is Accessibility permission granted?")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Method 2: NSEvent monitor as backup
        nsEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedNS(event)
        }

        logInfo("GlobeKeyMonitor started (CGEventTap + NSEvent)")
        return true
    }

    /// Stop monitoring Globe key events
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = nsEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        nsEventMonitor = nil
        logInfo("GlobeKeyMonitor stopped")
    }

    private nonisolated func handleFlagsChangedCG(_ event: CGEvent) {
        let flags = event.flags
        let rawFlags = flags.rawValue

        logDebug("[CGEvent] Flags: raw=0x\(String(rawFlags, radix: 16)), secondaryFn=\(flags.contains(.maskSecondaryFn))")

        let globePressed = flags.contains(.maskSecondaryFn)
        Task { @MainActor [weak self] in
            self?.handleGlobeState(pressed: globePressed, source: "CGEvent")
        }
    }

    private func handleFlagsChangedNS(_ event: NSEvent) {
        let flags = event.modifierFlags
        let rawFlags = flags.rawValue

        // NSEvent.ModifierFlags.function is the Fn/Globe key
        let globePressed = flags.contains(.function)

        logDebug("[NSEvent] Flags: raw=0x\(String(rawFlags, radix: 16)), function=\(globePressed)")

        handleGlobeState(pressed: globePressed, source: "NSEvent")
    }

    private func handleGlobeState(pressed: Bool, source: String) {
        if pressed && !isGlobePressed {
            isGlobePressed = true
            pressTime = Date()
            isHolding = false
            logDebug("Globe key down (via \(source))")
            
            // Schedule hold detection
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, self.isGlobePressed, !self.isHolding else { return }
                self.isHolding = true
                logInfo("Globe key hold started")
                self.onGlobeHoldStart?()
            }
        } else if !pressed && isGlobePressed {
            isGlobePressed = false
            let pressDuration = pressTime.map { Date().timeIntervalSince($0) } ?? 0
            
            if isHolding {
                // Was holding - trigger hold end
                logInfo("Globe key hold ended (held \(String(format: "%.2f", pressDuration))s)")
                isHolding = false
                onGlobeHoldEnd?()
            } else {
                // Quick tap
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

        if !trusted && prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        return trusted
    }
}
