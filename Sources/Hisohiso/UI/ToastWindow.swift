import AppKit

/// Transient non-modal toast window shown briefly at the bottom of the screen.
///
/// Displays a short message (e.g., "✓ Copied to clipboard") and auto-dismisses
/// after a configurable duration. Only one toast is shown at a time.
@MainActor
final class ToastWindow {
    private var window: NSWindow?

    /// Show a toast message. Any existing toast is dismissed immediately.
    /// - Parameters:
    ///   - message: The text to display.
    ///   - duration: Seconds before auto-dismiss (default: 1.5).
    func show(_ message: String, duration: TimeInterval = 1.5) {
        // Dismiss any existing toast
        dismiss()

        let width: CGFloat = 220
        let height: CGFloat = 36

        let toast = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.level = .screenSaver
        toast.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = height / 2
        label.frame = container.bounds
        container.addSubview(label)
        toast.contentView = container

        if let screen = NSScreen.main {
            let x = (screen.frame.width - width) / 2
            toast.setFrame(NSRect(x: x, y: 120, width: width, height: height), display: true)
        }

        self.window = toast
        toast.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismiss()
        }
    }

    /// Dismiss the current toast if visible.
    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}
