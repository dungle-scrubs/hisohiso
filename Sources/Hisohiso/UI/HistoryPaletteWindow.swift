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

    /// Allow panel to become key window
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

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
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
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
            guard let self, isVisible else { return event }
            return handleKeyDown(event) ? nil : event
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
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] event in
            guard let self, isVisible else { return event }

            // Convert click location to screen coordinates
            let clickLocation = event.locationInWindow
            if let eventWindow = event.window {
                let screenLocation = eventWindow.convertPoint(toScreen: clickLocation)
                // Check if click is outside our panel
                if !frame.contains(screenLocation) {
                    dismiss()
                    return nil // Consume the event
                }
            } else {
                // Click with no window (shouldn't happen but handle it)
                dismiss()
                return nil
            }
            return event
        }

        // Global monitor: catches clicks outside the app entirely
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] _ in
            guard let self, isVisible else { return }
            dismiss()
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
        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved,
            .mouseEntered,
            .mouseExited,
            .scrollWheel,
        ]) { [weak self] event in
            guard let self, isVisible else { return event }

            let locationInWindow = event.locationInWindow
            let scrollViewFrame = scrollView.frame
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
            makeFirstResponder(searchField)
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
        HistoryRowView()
    }
}
