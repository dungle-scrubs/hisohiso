import Cocoa
import os

/// Manages a single CGEventTap shared across all keyboard monitors.
///
/// macOS limits the number of event taps and each requires Accessibility permission.
/// A single tap is more reliable and reduces the permission surface.
///
/// ## Threading
/// The CGEventTap callback fires on an arbitrary thread. Registered handlers
/// must be `@Sendable` and must not touch `@MainActor`-isolated state directly.
/// Use `Task { @MainActor in … }` for any MainActor work, but note the callback
/// must return synchronously (whether to consume the event).
final class EventTapManager: @unchecked Sendable {
    static let shared = EventTapManager()

    /// A registered event handler.
    private struct Registration {
        let id: String
        let eventTypes: Set<CGEventType>
        /// Return `true` to consume the event (prevent it from reaching other apps).
        let handler: @Sendable (_ event: CGEvent, _ type: CGEventType) -> Bool
    }

    private var registrations: [Registration] = []
    private let lock = os.OSAllocatedUnfairLock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Event mask the running tap was created with.
    private var currentEventMask: CGEventMask = 0

    private init() {}

    // MARK: - Registration

    /// Register a handler for specific event types.
    ///
    /// If the tap is already running it will be restarted to include any new event types.
    /// - Parameters:
    ///   - id: Unique identifier (re-registering the same id replaces the previous handler).
    ///   - eventTypes: CGEvent types this handler cares about.
    ///   - handler: Called on an arbitrary thread. Return `true` to consume the event.
    func register(
        id: String,
        eventTypes: Set<CGEventType>,
        handler: @escaping @Sendable (_ event: CGEvent, _ type: CGEventType) -> Bool
    ) {
        lock.withLock {
            registrations.removeAll { $0.id == id }
            registrations.append(Registration(id: id, eventTypes: eventTypes, handler: handler))
        }

        // Only restart the tap if the combined event mask changed
        if eventTap != nil {
            let newMask: CGEventMask = lock.withLock {
                var mask: CGEventMask = 0
                for reg in registrations {
                    for type in reg.eventTypes {
                        mask |= (1 << type.rawValue)
                    }
                }
                return mask
            }
            if newMask != currentEventMask {
                stopTap()
                _ = startTap()
            }
        }
    }

    /// Unregister a handler by id.
    func unregister(id: String) {
        lock.withLock {
            registrations.removeAll { $0.id == id }
        }

        // Stop the tap if no handlers remain
        let isEmpty = lock.withLock { registrations.isEmpty }
        if isEmpty {
            stopTap()
        }
    }

    // MARK: - Lifecycle

    /// Start the shared event tap. Safe to call multiple times.
    /// - Returns: `true` if the tap is running (or was already running).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        return startTap()
    }

    /// Stop the shared event tap.
    func stop() {
        stopTap()
    }

    // MARK: - Private

    private func startTap() -> Bool {
        let allEventTypes = lock.withLock {
            registrations.reduce(into: Set<CGEventType>()) { $0.formUnion($1.eventTypes) }
        }

        guard !allEventTypes.isEmpty else {
            logWarning("EventTapManager: no handlers registered, not starting")
            return false
        }

        var eventMask: CGEventMask = 0
        for type in allEventTypes {
            eventMask |= (1 << type.rawValue)
        }

        // Save for comparison
        currentEventMask = eventMask

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

                // Re-enable on timeout or user input disabling
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Safety: never block the event tap for too long.
                // All handlers must return synchronously and quickly.
                // Heavy work should be dispatched to MainActor via Task.
                let consumed = manager.dispatch(event: event, type: type)
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logError("EventTapManager: failed to create event tap. Is Accessibility permission granted?")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logInfo("EventTapManager: started with event types: \(allEventTypes.map(\.rawValue))")
        return true
    }

    private func stopTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        currentEventMask = 0
        logInfo("EventTapManager: stopped")
    }

    /// Dispatch an event to all matching handlers.
    ///
    /// Called on the event tap's thread (arbitrary). Handlers **must** return
    /// quickly — blocking here freezes all keyboard input system-wide.
    /// Heavy work (UI updates, async operations) should be dispatched via
    /// `Task { @MainActor in … }` from within the handler.
    private func dispatch(event: CGEvent, type: CGEventType) -> Bool {
        let handlers = lock.withLock {
            registrations.filter { $0.eventTypes.contains(type) }
        }

        for registration in handlers where registration.handler(event, type) {
            return true // consumed
        }
        return false
    }
}
