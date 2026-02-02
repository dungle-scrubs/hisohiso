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
            return "Accessibility permission not granted"
        case .insertionFailed:
            return "Failed to insert text"
        }
    }
}

/// Inserts text at the current cursor position using keyboard events
final class TextInserter {
    /// Maximum text length for direct character insertion (longer uses paste)
    private let directInsertionThreshold = 100

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

    /// Insert text character by character using keyboard events
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

            // Small delay to prevent dropped characters
            usleep(1000) // 1ms
        }
    }

    /// Insert text using the clipboard and Cmd+V
    private func insertViaPaste(_ text: String) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set clipboard to our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulateCommandV()

        // Restore previous clipboard after a delay
        let previous = previousContents
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(previous, forType: .string)
            }
        }
    }

    /// Simulate Cmd+V keystroke
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)

        // V key code is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
