import Foundation

/// Turns press and release events for one key into tap and hold gestures.
///
/// A press followed by a release within `holdThreshold` is a tap. A press that
/// outlasts the threshold starts a hold, and the matching release ends it.
/// `GlobeKeyMonitor` and `HotkeyManager` both feed this detector so every
/// activation key shares one set of timing rules.
@MainActor
final class PressGestureDetector {
    /// Called on release when the press was shorter than the hold threshold.
    var onTap: (@MainActor () -> Void)?

    /// Called once the key has been held for the hold threshold.
    var onHoldStart: (@MainActor () -> Void)?

    /// Called on release after `onHoldStart` fired.
    var onHoldEnd: (@MainActor () -> Void)?

    /// Whether the key is currently down.
    private(set) var isPressed = false

    /// Whether the current press has crossed the hold threshold.
    private(set) var isHolding = false

    private let holdThreshold: TimeInterval
    private var pressTime: Date?
    private var holdTask: Task<Void, Never>?

    /// - Parameter holdThreshold: Seconds a key must stay down to count as a hold.
    init(holdThreshold: TimeInterval = AppConstants.activationHoldThreshold) {
        self.holdThreshold = holdThreshold
    }

    /// Record a key-down. Repeated presses without a release are ignored.
    func press() {
        guard !isPressed else { return }
        isPressed = true
        isHolding = false
        pressTime = Date()

        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.holdThreshold ?? 0))
            guard !Task.isCancelled, let self, isPressed, !isHolding else { return }
            isHolding = true
            onHoldStart?()
        }
    }

    /// Record a key-up. Fires `onTap` or `onHoldEnd` depending on press duration.
    func release() {
        guard isPressed else { return }
        isPressed = false
        holdTask?.cancel()
        holdTask = nil

        let pressDuration = pressTime.map { Date().timeIntervalSince($0) } ?? 0
        pressTime = nil

        if isHolding {
            isHolding = false
            logInfo("Activation key hold ended (held \(String(format: "%.2f", pressDuration))s)")
            onHoldEnd?()
        } else {
            logInfo("Activation key tapped")
            onTap?()
        }
    }

    /// Drop any in-flight press without firing a gesture.
    func reset() {
        holdTask?.cancel()
        holdTask = nil
        isPressed = false
        isHolding = false
        pressTime = nil
    }
}
