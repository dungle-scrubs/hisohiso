import Cocoa

// MARK: - Setup Error Presentation

extension AppDelegate {
    func showInitializationError(_ error: Error) {
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
            alert.informativeText = """
            Hisohiso encountered an error during setup:

            \(error.localizedDescription)

            Try restarting the app. If the problem persists, check that you have enough disk space for model downloads.
            """
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
                    // For non-permission errors, don't open System Settings
                    return
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
