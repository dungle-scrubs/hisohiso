import Cocoa
import SwiftUI

/// Floating pill indicator at the bottom of the screen
final class FloatingPillWindow: NSWindow {
    private var hostingView: NSHostingView<FloatingPillView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver  // Higher level to appear over everything
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hasShadow = true
        ignoresMouseEvents = false // Allow clicks for retry button
        
        // Force visibility
        alphaValue = 1.0
    }

    /// Show the pill with the given state
    /// - Parameters:
    ///   - state: Current recording state
    ///   - onDismiss: Called when user dismisses the pill
    ///   - onRetry: Called when user clicks retry
    func show(state: RecordingState, onDismiss: @escaping () -> Void, onRetry: @escaping () -> Void) {
        if case .idle = state {
            orderOut(nil)
            return
        }

        // Use AppKit directly (SwiftUI NSHostingView has issues)
        let pillView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 44))
        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        pillView.layer?.cornerRadius = 22
        
        let label = NSTextField(labelWithString: state.displayText)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 12, width: 180, height: 20)
        pillView.addSubview(label)
        
        // Red dot for recording
        if case .recording = state {
            let dot = NSView(frame: NSRect(x: 20, y: 17, width: 10, height: 10))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.red.cgColor
            dot.layer?.cornerRadius = 5
            pillView.addSubview(dot)
        }
        
        contentView = pillView

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
            // Recalculate frame based on content
            let idealWidth: CGFloat
            if case .error = state {
                idealWidth = 320
            } else {
                idealWidth = 180
            }

            let frame = NSRect(
                x: (screen.frame.width - idealWidth) / 2,
                y: 80, // Above dock
                width: idealWidth,
                height: 44
            )
            setFrame(frame, display: true)
            logInfo("FloatingPill frame set: \(frame)")
        } else {
            logWarning("FloatingPill: No main screen found!")
        }

        makeKeyAndOrderFront(nil)
    }

    /// Hide the pill
    func hide() {
        orderOut(nil)
    }
}

// MARK: - SwiftUI View

struct FloatingPillView: View {
    let state: RecordingState
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .modifier(PulseAnimation())
                Text("Recording...")
                    .font(.system(size: 13, weight: .medium))

            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("Transcribing...")
                    .font(.system(size: 13, weight: .medium))

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Button(action: onRetry) {
                    Text("Retry")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

            case .idle:
                EmptyView()
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        )
    }
}

// MARK: - Pulse Animation Modifier

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Recording") {
    FloatingPillView(state: .recording, onDismiss: {}, onRetry: {})
        .padding()
        .background(.gray)
}

#Preview("Transcribing") {
    FloatingPillView(state: .transcribing, onDismiss: {}, onRetry: {})
        .padding()
        .background(.gray)
}

#Preview("Error") {
    FloatingPillView(state: .error(message: "Transcription timed out"), onDismiss: {}, onRetry: {})
        .padding()
        .background(.gray)
}
#endif
