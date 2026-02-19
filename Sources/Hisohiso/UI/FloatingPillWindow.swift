import Cocoa
import SwiftUI

/// View that responds to clicks
private class ClickableView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Animated waveform view using Core Animation tuned to match Sinew visuals
private class WaveformView: NSView {
    private var barLayers: [CALayer] = []
    private var barsCreated = false
    // Match Sinew config defaults: bar_width=3, bar_gap=2, max_height=20, min_height=4
    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 20
    private let minBarHeight: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    private func createBarsIfNeeded() {
        guard !barsCreated, bounds.width > 0 else { return }
        barsCreated = true

        layer?.masksToBounds = false

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2

        for i in 0 ..< barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = 1 // Match Sinew: rounded(px(1.0))

            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            // All bars start at same minBarHeight
            bar.frame = CGRect(
                x: x,
                y: (bounds.height - minBarHeight) / 2,
                width: barWidth,
                height: minBarHeight
            )

            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    /// Update waveform with audio levels (0-100 for each bar)
    func updateLevels(_ levels: [UInt8]) {
        createBarsIfNeeded()
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        for (i, bar) in barLayers.enumerated() {
            let rawLevel = i < levels.count ? CGFloat(levels[i]) : 0
            // Match Sinew: amplify 5x, cap at 100
            let level = min(rawLevel * 5.0, 100.0) / 100.0
            let height = minBarHeight + (maxBarHeight - minBarHeight) * level
            let y = (bounds.height - height) / 2

            bar.frame = CGRect(
                x: bar.frame.origin.x,
                y: y,
                width: barWidth,
                height: height
            )
        }

        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        createBarsIfNeeded()

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2

        for (i, bar) in barLayers.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            var frame = bar.frame
            frame.origin.x = x
            // Keep height but re-center vertically
            frame.origin.y = (bounds.height - frame.height) / 2
            bar.frame = frame
        }
    }
}

/// Floating pill indicator at the bottom of the screen
final class FloatingPillWindow: NSWindow {
    private var hostingView: NSHostingView<FloatingPillView>?
    private var waveformView: WaveformView?
    private var currentState: RecordingState = .idle

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver // Higher level to appear over everything
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hasShadow = true
        ignoresMouseEvents = false // Allow clicks for retry button

        // Force visibility
        alphaValue = 1.0
    }

    private var autoDismissTimer: Timer?

    /// Update audio levels for waveform animation (call frequently during recording)
    func updateAudioLevels(_ levels: [UInt8]) {
        guard case .recording = currentState else { return }
        waveformView?.updateLevels(levels)
    }

    /// Show the pill with the given state
    /// - Parameters:
    ///   - state: Current recording state
    ///   - onDismiss: Called when user dismisses the pill
    ///   - onRetry: Called when user clicks retry
    func show(state: RecordingState, onDismiss: @escaping () -> Void, onRetry: @escaping () -> Void) {
        // Cancel any pending auto-dismiss
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        currentState = state

        if case .idle = state {
            orderOut(nil)
            waveformView = nil
            return
        }

        // Determine pill width
        let idealWidth: CGFloat
        if case .error = state {
            idealWidth = 320
        } else {
            idealWidth = 100
        }

        // Use AppKit directly (SwiftUI NSHostingView has issues)
        let pillView = ClickableView(frame: NSRect(x: 0, y: 0, width: idealWidth, height: 44))
        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        pillView.layer?.cornerRadius = 22
        pillView.onClick = { [weak self] in
            self?.orderOut(nil)
            self?.waveformView = nil
            onDismiss()
        }

        if case .recording = state {
            // Waveform for recording state
            let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: idealWidth, height: 44))
            pillView.addSubview(waveform)
            waveformView = waveform
        } else if case .transcribing = state {
            // Keep waveform visible during transcription (frozen)
            // Don't create new waveform, just keep the existing one if present
            if let existingWaveform = waveformView {
                existingWaveform.frame = NSRect(x: 0, y: 0, width: idealWidth, height: 44)
                pillView.addSubview(existingWaveform)
            } else {
                // Fallback: create static waveform
                let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: idealWidth, height: 44))
                pillView.addSubview(waveform)
                waveformView = waveform
            }
        } else {
            // Text label for error states
            let label = NSTextField(labelWithString: state.displayText)
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 12, width: idealWidth, height: 20)
            pillView.addSubview(label)
            waveformView = nil
        }

        contentView = pillView

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
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

        // Auto-dismiss error after 3 seconds
        if case .error = state {
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.orderOut(nil)
                self?.waveformView = nil
                onDismiss()
            }
        }
    }

    /// Hide the pill
    func hide() {
        orderOut(nil)
        waveformView = nil
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
