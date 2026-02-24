import AppKit
import Carbon.HIToolbox

// MARK: - HistoryPaletteWindow

/// Spotlight-style command palette for browsing transcription history
final class HistoryPaletteWindow: NSPanel {
    private let searchField = NSTextField()
    private let scrollView = NSScrollView()
    private let tableView = PointerTableView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var records: [TranscriptionRecord] = []
    private var filteredRecords: [TranscriptionRecord] = []
    private var selectedIndex: Int = 0
    private var localKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var mouseMovedMonitor: Any?

    /// Callback when user selects a record
    var onSelect: ((TranscriptionRecord) -> Void)?

    /// Callback when window is dismissed
    var onDismiss: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )

        setupWindow()
        setupViews()
    }

    private func setupWindow() {
        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        hasShadow = true
        acceptsMouseMovedEvents = true

        // Critical for NSPanel to accept key input
        becomesKeyOnlyIfNeeded = false
    }

    // Allow panel to become key window
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func setupViews() {
        // Background view with solid dark background + rounded corners
        let backgroundView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        backgroundView.layer?.borderWidth = 1
        contentView = backgroundView

        // Search field
        searchField.frame = NSRect(x: 16, y: 358, width: 568, height: 30)
        searchField.placeholderString = "Search history..."
        searchField.font = .systemFont(ofSize: 18, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = .white
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
        
        // Style placeholder
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.5, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 18, weight: .regular)
        ]
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search history...",
            attributes: placeholderAttrs
        )
        backgroundView.addSubview(searchField)

        // Divider
        let divider = NSBox(frame: NSRect(x: 16, y: 350, width: 568, height: 1))
        divider.boxType = .custom
        divider.fillColor = NSColor(white: 0.3, alpha: 1.0)
        divider.borderWidth = 0
        backgroundView.addSubview(divider)

        // Table view
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = 56
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.action = #selector(tableViewClicked)
        tableView.doubleAction = #selector(tableViewDoubleClicked)
        tableView.target = self
        tableView.gridColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("record"))
        column.width = 568
        tableView.addTableColumn(column)

        // Scroll view - use custom clip view to prevent cursor interference
        let clipView = NoIBeamClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.frame = NSRect(x: 0, y: 8, width: 600, height: 338)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        backgroundView.addSubview(scrollView)

        // Empty state label
        emptyLabel.frame = NSRect(x: 0, y: 150, width: 600, height: 60)
        emptyLabel.stringValue = "No history yet.\nUse Globe key to dictate."
        emptyLabel.alignment = .center
        emptyLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isHidden = true
        backgroundView.addSubview(emptyLabel)
    }

    // MARK: - Key Handling

    private func setupKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func setupClickOutsideMonitor() {
        // Local monitor: catches clicks within the app - check if outside our window
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            
            // Convert click location to screen coordinates
            let clickLocation = event.locationInWindow
            if let eventWindow = event.window {
                let screenLocation = eventWindow.convertPoint(toScreen: clickLocation)
                // Check if click is outside our panel
                if !self.frame.contains(screenLocation) {
                    self.dismiss()
                    return nil // Consume the event
                }
            } else {
                // Click with no window (shouldn't happen but handle it)
                self.dismiss()
                return nil
            }
            return event
        }
        
        // Global monitor: catches clicks outside the app entirely
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            self.dismiss()
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func setupCursorMonitor() {
        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .scrollWheel]) { [weak self] event in
            guard let self, self.isVisible else { return event }

            let locationInWindow = event.locationInWindow
            let scrollViewFrame = self.scrollView.frame
            let scrollerWidth: CGFloat = 15
            let tableAreaFrame = NSRect(
                x: scrollViewFrame.origin.x,
                y: scrollViewFrame.origin.y,
                width: scrollViewFrame.width - scrollerWidth,
                height: scrollViewFrame.height
            )

            if tableAreaFrame.contains(locationInWindow) {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }

            return event
        }
    }

    private func removeCursorMonitor() {
        if let monitor = mouseMovedMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMovedMonitor = nil
        }
        NSCursor.arrow.set()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            dismiss()
            return true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            selectCurrentItem()
            return true

        case kVK_UpArrow:
            moveSelection(by: -1)
            return true

        case kVK_DownArrow:
            moveSelection(by: 1)
            return true

        default:
            return false
        }
    }

    // MARK: - Public API

    /// Show the palette centered on screen
    func showPalette() {
        // Load fresh data
        reloadData()

        // Clear search and reset selection
        searchField.stringValue = ""
        filteredRecords = records
        selectedIndex = 0
        tableView.reloadData()
        updateSelection()
        updateEmptyState()

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 300
            let y = screenFrame.midY - 200 + 100
            setFrame(NSRect(x: x, y: y, width: 600, height: 400), display: true)
        }

        setupKeyMonitor()
        setupClickOutsideMonitor()
        setupCursorMonitor()

        // Activate app and show window
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        
        // Force first responder to search field
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.makeFirstResponder(self.searchField)
        }

        logInfo("History palette shown with \(records.count) records")
    }

    /// Dismiss the palette
    func dismiss() {
        removeKeyMonitor()
        removeClickOutsideMonitor()
        removeCursorMonitor()
        orderOut(nil)
        onDismiss?()
        logInfo("History palette dismissed")
    }

    // MARK: - Private Helpers

    private func reloadData() {
        records = HistoryStore.shared.recent(limit: 100)
    }

    private func filterRecords(query: String) {
        if query.isEmpty {
            filteredRecords = records
        } else {
            filteredRecords = HistoryStore.shared.search(query: query)
        }

        selectedIndex = 0
        tableView.reloadData()
        updateSelection()
        updateEmptyState()
    }

    private func moveSelection(by delta: Int) {
        guard !filteredRecords.isEmpty else { return }

        selectedIndex = max(0, min(filteredRecords.count - 1, selectedIndex + delta))
        updateSelection()
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func updateSelection() {
        guard !filteredRecords.isEmpty, selectedIndex >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !filteredRecords.isEmpty
        scrollView.isHidden = filteredRecords.isEmpty
    }

    private func selectCurrentItem() {
        guard selectedIndex >= 0, selectedIndex < filteredRecords.count else { return }

        let record = filteredRecords[selectedIndex]
        dismiss()
        onSelect?(record)
    }

    @objc private func searchFieldAction() {
        selectCurrentItem()
    }

    @objc private func tableViewClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredRecords.count else { return }
        selectedIndex = row
        selectCurrentItem()
    }

    @objc private func tableViewDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredRecords.count else { return }

        selectedIndex = row
        selectCurrentItem()
    }
}

// MARK: - NSTextFieldDelegate

extension HistoryPaletteWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filterRecords(query: searchField.stringValue)
    }
}

// MARK: - NSTableViewDataSource

extension HistoryPaletteWindow: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }
}

// MARK: - NSTableViewDelegate

extension HistoryPaletteWindow: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredRecords.count else { return nil }

        let record = filteredRecords[row]

        let cellIdentifier = NSUserInterfaceItemIdentifier("HistoryCell")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? HistoryRecordCellView

        if cellView == nil {
            cellView = HistoryRecordCellView()
            cellView?.identifier = cellIdentifier
        }

        cellView?.configure(with: record)
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.selectedRow >= 0 {
            selectedIndex = tableView.selectedRow
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HistoryRowView()
        return rowView
    }
}

// MARK: - HistoryRowView

private final class HistoryRowView: NSTableRowView {
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
        // Select this row on hover
        if let tableView = superview as? NSTableView {
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
            let selectionRect = bounds.insetBy(dx: 8, dy: 1)
            NSColor(white: 0.3, alpha: 1.0).setFill()
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

private final class NoIBeamClipView: NSClipView {
    override func resetCursorRects() {
        // Don't set any cursor rects
    }
}

// MARK: - PointerTableView

private final class PointerTableView: NSTableView {
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

private final class NonSelectableTextField: NSTextField {
    override func resetCursorRects() {
        // Don't add any cursor rects - let parent handle it
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through all mouse events to parent
        return nil
    }
}

// MARK: - HistoryRecordCellView

private final class HistoryRecordCellView: NSTableCellView {
    private let textLabel = NonSelectableTextField(labelWithString: "")
    private let timestampLabel = NonSelectableTextField(labelWithString: "")

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through to row view for cursor handling
        return nil
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
        textLabel.font = .systemFont(ofSize: 13, weight: .regular)
        textLabel.textColor = .white
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 2
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.drawsBackground = false
        textLabel.isBezeled = false
        textLabel.isSelectable = false

        timestampLabel.font = .systemFont(ofSize: 11, weight: .regular)
        timestampLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        timestampLabel.drawsBackground = false
        timestampLabel.isBezeled = false
        timestampLabel.isSelectable = false

        addSubview(textLabel)
        addSubview(timestampLabel)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            timestampLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 2),
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
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
