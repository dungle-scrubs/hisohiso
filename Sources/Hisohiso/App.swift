import Cocoa
import Combine
import SwiftUI

/// Main application entry point
@main
struct HisohisoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app - no main window
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPill: FloatingPillWindow?
    private var dictationController: DictationController?
    private var modelManager: ModelManager?
    private var hotkeyManager: HotkeyManager?
    private var stateObserver: AnyCancellable?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var historyPalette: HistoryPaletteWindow?
    private var historyHotkeyMonitor: HistoryHotkeyMonitor?

    /// UserDefaults key for tracking first launch
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        logInfo("Hisohiso starting...")
        logInfo("Log file: \(Logger.shared.logFilePath)")

        modelManager = ModelManager()
        setupStatusItem()
        setupFloatingPill()
        setupHistoryPalette()
        setupHistoryHotkey()

        // Check if first launch
        if !UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) {
            showOnboarding()
        } else {
            setupDictationController()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictationController?.shutdown()
        historyHotkeyMonitor?.stop()
        hotkeyManager?.stop()
        logInfo("Hisohiso shutting down")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use text as fallback if SF Symbol fails
            if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hisohiso") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
            } else {
                // Fallback to text
                button.title = "🎤"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        logInfo("Status item created")
    }

    private func setupFloatingPill() {
        floatingPill = FloatingPillWindow()
        logInfo("Floating pill created")
    }

    private func setupHistoryPalette() {
        historyPalette = HistoryPaletteWindow()
        historyPalette?.onSelect = { [weak self] record in
            self?.handleHistorySelection(record)
        }
        logInfo("History palette created")
    }

    private func setupHistoryHotkey() {
        historyHotkeyMonitor = HistoryHotkeyMonitor()
        historyHotkeyMonitor?.onHotkey = { [weak self] in
            self?.toggleHistoryPalette()
        }
        historyHotkeyMonitor?.start()
        logInfo("History hotkey monitor started (⌃⌥Space)")
    }

    private func toggleHistoryPalette() {
        guard let palette = historyPalette else { return }

        if palette.isVisible {
            palette.dismiss()
        } else {
            palette.showPalette()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func handleHistorySelection(_ record: TranscriptionRecord) {
        logInfo("History item selected: \(record.text.prefix(50))...")

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)

        // Also insert at cursor if possible
        let textInserter = TextInserter()
        do {
            try textInserter.insert(record.text)
            logInfo("Inserted history text at cursor")
        } catch {
            logWarning("Could not insert at cursor, copied to clipboard: \(error)")
            // Show notification that text was copied
            showCopiedNotification()
        }
    }

    private func showCopiedNotification() {
        // Brief visual feedback that text was copied
        let alert = NSAlert()
        alert.messageText = "Copied to Clipboard"
        alert.informativeText = "The text has been copied. Press ⌘V to paste."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        // Auto-dismiss after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.stopModal()
        }

        alert.runModal()
    }

    private func setupDictationController() {
        guard let modelManager else { return }

        // Setup alternative hotkey manager
        hotkeyManager = HotkeyManager()

        dictationController = DictationController(modelManager: modelManager, hotkeyManager: hotkeyManager)

        // Observe state changes to update floating pill
        if let controller = dictationController {
            stateObserver = controller.stateManager.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.updateFloatingPill(for: state)
                }
        }

        // Initialize in background
        Task { [weak self] in
            do {
                try await self?.dictationController?.initialize()
            } catch {
                logError("Failed to initialize dictation controller: \(error)")
                self?.showInitializationError(error)
            }
        }
    }

    private func updateFloatingPill(for state: RecordingState) {
        logInfo("updateFloatingPill called with state: \(state)")
        floatingPill?.show(
            state: state,
            onDismiss: { [weak self] in
                self?.dictationController?.stateManager.setIdle()
            },
            onRetry: { [weak self] in
                self?.dictationController?.stateManager.retry()
            }
        )
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            showPreferences()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Test UI", action: #selector(testUI), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hisohiso", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so left-click works
    }
    
    @objc private func testUI() {
        logInfo("testUI called - showing pill")
        dictationController?.stateManager.setRecording()
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dictationController?.stateManager.setIdle()
        }
    }
    
    private func showOnboarding() {
        logInfo("Showing onboarding")
        onboardingWindow = OnboardingWindow { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: self.hasCompletedOnboardingKey)
            self.onboardingWindow = nil
            self.setupDictationController()
            logInfo("Onboarding completed")
        }
        
        if let window = onboardingWindow {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            logInfo("Onboarding window: frame=\(window.frame), isVisible=\(window.isVisible)")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        logInfo("Show preferences")

        guard let modelManager else { return }

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(modelManager: modelManager, hotkeyManager: hotkeyManager)
        }

        if let window = preferencesWindow {
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.makeMain()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showInitializationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Hisohiso Setup Required"

        // Provide specific instructions based on error type
        if let dictationError = error as? DictationError {
            switch dictationError {
            case .accessibilityPermissionDenied:
                alert.informativeText = """
                    Hisohiso needs Accessibility permission to capture the Globe key and insert text.

                    1. Click "Open System Settings"
                    2. Find Hisohiso in the list and enable it
                    3. If not in list, click + and add this app
                    4. Restart Hisohiso
                    """
            case .microphonePermissionDenied:
                alert.informativeText = """
                    Hisohiso needs Microphone permission to record audio for transcription.

                    Click "Open System Settings" and enable Microphone access.
                    """
            default:
                alert.informativeText = error.localizedDescription
            }
        } else {
            alert.informativeText = error.localizedDescription
        }

        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open directly to Accessibility settings
            if let dictationError = error as? DictationError {
                let urlString: String
                switch dictationError {
                case .accessibilityPermissionDenied:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                case .microphonePermissionDenied:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                default:
                    urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy"
                }
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}
