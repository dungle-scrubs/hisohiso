import Cocoa
import os

/// Thread-safe registry for event tap handlers.
///
/// `EventTapManager` owns the macOS event tap lifecycle. This registry owns the
/// mutable handler list behind one explicit lock so callback dispatch can be
/// tested without creating a real CGEventTap.
final class EventTapRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (_ event: CGEvent, _ type: CGEventType) -> Bool

    /// A registered event tap handler.
    struct Registration: Sendable {
        let id: String
        let eventTypes: Set<CGEventType>
        let handler: Handler
    }

    private var registrations: [Registration] = []
    private let lock = os.OSAllocatedUnfairLock()

    /// Register or replace a handler.
    /// - Parameters:
    ///   - id: Unique handler identifier.
    ///   - eventTypes: Event types the handler receives.
    ///   - handler: Synchronous event handler.
    func register(id: String, eventTypes: Set<CGEventType>, handler: @escaping Handler) {
        lock.withLock {
            registrations.removeAll { $0.id == id }
            registrations.append(Registration(id: id, eventTypes: eventTypes, handler: handler))
        }
    }

    /// Remove a handler by identifier.
    /// - Parameter id: Handler identifier to remove.
    func unregister(id: String) {
        lock.withLock {
            registrations.removeAll { $0.id == id }
        }
    }

    /// Return whether no handlers are registered.
    /// - Returns: `true` when the registry is empty.
    var isEmpty: Bool {
        lock.withLock { registrations.isEmpty }
    }

    /// Compute the combined CGEvent mask for all registrations.
    /// - Returns: Event mask for CGEventTap creation.
    func eventMask() -> CGEventMask {
        lock.withLock {
            registrations.reduce(into: CGEventMask(0)) { mask, registration in
                for type in registration.eventTypes {
                    mask |= (1 << type.rawValue)
                }
            }
        }
    }

    /// Dispatch one event to matching handlers in registration order.
    /// - Parameters:
    ///   - event: Event received from the tap.
    ///   - type: Event type received from the tap.
    /// - Returns: `true` when a handler consumed the event.
    func dispatch(event: CGEvent, type: CGEventType) -> Bool {
        let handlers = lock.withLock {
            registrations.filter { $0.eventTypes.contains(type) }
        }

        for registration in handlers where registration.handler(event, type) {
            return true
        }
        return false
    }
}
