import Carbon
import Cocoa
import Foundation

/// Error types for text insertion
enum TextInserterError: Error, LocalizedError {
    case accessibilityNotGranted
    case insertionFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            "Accessibility permission not granted"
        case .insertionFailed:
            "Failed to insert text"
        }
    }
}

/// Inserts text at the current cursor position using keyboard events
final class TextInserter {
    /// Maximum text length for direct character insertion (longer uses paste).
    /// Set conservatively low — per-character insertion uses usleep which blocks.
    /// Paste is faster and preferred for almost all real dictation output.
    private let directInsertionThreshold = AppConstants.directInsertionThreshold

    /// Insert text at the current cursor position
    /// - Parameter text: Text to insert
    /// - Throws: TextInserterError if insertion fails
    func insert(_ text: String) throws {
        guard GlobeKeyMonitor.checkAccessibilityPermission() else {
            throw TextInserterError.accessibilityNotGranted
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            logWarning("Empty text, nothing to insert")
            return
        }

        logInfo("Inserting text: \(trimmedText.prefix(50))...")

        // Use paste for longer text (faster)
        if trimmedText.count > directInsertionThreshold {
            insertViaPaste(trimmedText)
        } else {
            insertViaKeyEvents(trimmedText)
        }
    }

    /// Insert text character by character using keyboard events.
    /// Only used for very short strings (≤10 chars). macOS 14+ queues
    /// CGEvents reliably without artificial inter-character delays.
    private func insertViaKeyEvents(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            var unicodeChars = Array(String(char).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
            keyUp?.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)

            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Insert text using the clipboard and Cmd+V.
    /// Preserves all pasteboard item types and restores only if clipboard has not changed.
    private func insertViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = Self.snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            logWarning("Failed to set pasteboard string; falling back to key events")
            insertViaKeyEvents(text)
            return
        }

        let expectedChangeCount = pasteboard.changeCount

        // Simulate Cmd+V
        simulateCommandV()

        // Restore clipboard after a delay, but only if user/app did not change it.
        // 500ms gives slow apps (Electron, browsers with extensions) time to process Cmd+V.
        // Tradeoff: user's original clipboard is unavailable for 500ms after dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.pasteRestoreDelay) {
            let currentPasteboard = NSPasteboard.general
            guard currentPasteboard.changeCount == expectedChangeCount else {
                return
            }
            Self.restorePasteboard(snapshot, to: currentPasteboard)
        }
    }

    /// Snapshot all pasteboard items and data representations.
    /// - Parameter pasteboard: Pasteboard to snapshot.
    /// - Returns: Serialized items keyed by pasteboard type.
    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.map { item in
            var snapshot = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        }
    }

    /// Restore pasteboard from a previous snapshot.
    /// - Parameters:
    ///   - snapshot: Snapshot captured by `snapshotPasteboard`.
    ///   - pasteboard: Pasteboard to restore.
    private static func restorePasteboard(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items: [NSPasteboardItem] = snapshot.compactMap { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item.types.isEmpty ? nil : item
        }

        if !items.isEmpty {
            _ = pasteboard.writeObjects(items)
        }
    }

    /// Simulate Cmd+V keystroke
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)

        // V key code is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: AppConstants.vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: AppConstants.vKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
