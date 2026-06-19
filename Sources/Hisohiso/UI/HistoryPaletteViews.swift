// View components used by `HistoryPaletteWindow` — row views, cell views,
// and cursor-management helpers for the history palette table.

import AppKit
import Carbon.HIToolbox

// MARK: - HistoryRowView

final class HistoryRowView: NSTableRowView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.push()
        // Select this row on hover — but not during keyboard navigation,
        // because scrolling shifts which row is under the stationary cursor.
        if let tableView = superview as? PointerTableView, !tableView.isKeyboardNavigating {
            let row = tableView.row(for: self)
            if row >= 0 {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionRect = bounds.insetBy(dx: 6, dy: 1)
            // Accent-tinted selection
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            path.fill()
        }
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

// MARK: - NoIBeamClipView

final class NoIBeamClipView: NSClipView {
    override func resetCursorRects() {
        // Don't set any cursor rects
    }
}

// MARK: - PointerTableView

final class PointerTableView: NSTableView {
    /// Set during keyboard navigation to suppress hover-to-select.
    var isKeyboardNavigating = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        // Don't call super - we handle cursor via tracking area
    }
}

// MARK: - NonSelectableTextField

final class NonSelectableTextField: NSTextField {
    override func resetCursorRects() {
        // Don't add any cursor rects - let parent handle it
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through all mouse events to parent
        nil
    }
}

// MARK: - HistoryRecordCellView

final class HistoryRecordCellView: NSTableCellView {
    private let textLabel = NonSelectableTextField(labelWithString: "")
    private let timestampLabel = NonSelectableTextField(labelWithString: "")

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through to row view for cursor handling
        nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Primary text — single line, truncated
        textLabel.font = .systemFont(ofSize: 13, weight: .regular)
        textLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.drawsBackground = false
        textLabel.isBezeled = false
        textLabel.isSelectable = false

        // Timestamp — right-aligned, subtle
        timestampLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timestampLabel.textColor = NSColor(white: 0.42, alpha: 1.0)
        timestampLabel.alignment = .right
        timestampLabel.drawsBackground = false
        timestampLabel.isBezeled = false
        timestampLabel.isSelectable = false
        timestampLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timestampLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(textLabel)
        addSubview(timestampLabel)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Text — vertically centered, stretches to fill
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -12),

            // Timestamp — vertically centered, right-aligned, intrinsic width
            timestampLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    /// Shared formatter instance — `RelativeDateTimeFormatter` is expensive to create.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func configure(with record: TranscriptionRecord) {
        textLabel.stringValue = record.text
        timestampLabel.stringValue = Self.relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date())
    }
}
