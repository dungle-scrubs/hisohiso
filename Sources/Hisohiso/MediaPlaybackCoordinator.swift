import Foundation

@MainActor
protocol MediaPlaybackControlling: AnyObject {
    func pausePlayingMedia() async -> Set<MediaPlaybackTarget>
    func resumeMedia(_ targets: Set<MediaPlaybackTarget>)
}

enum MediaPlaybackTarget: String, CaseIterable {
    case music
    case spotify
    case safari
    case chrome
    case edge
    case brave
    case arc
    case vlc
}

/// Pauses active media while dictation records, then restores only what it paused.
@MainActor
final class MediaPlaybackCoordinator {
    private let controller: any MediaPlaybackControlling
    private var pausedTargets = Set<MediaPlaybackTarget>()

    init(controller: any MediaPlaybackControlling = AppleScriptMediaPlaybackController()) {
        self.controller = controller
    }

    func pauseForRecording() async {
        guard pausedTargets.isEmpty else { return }
        pausedTargets = await controller.pausePlayingMedia()
    }

    func resumeAfterRecording() {
        guard !pausedTargets.isEmpty else { return }
        let targets = pausedTargets
        pausedTargets.removeAll()
        controller.resumeMedia(targets)
    }
}

// MARK: - Target Descriptors

/// Describes a media app that can be paused via AppleScript.
private protocol MediaTarget: Sendable {
    var target: MediaPlaybackTarget { get }
    var bundleID: String { get }
    func pauseBlock() -> String
    func resumeBlock() -> String
}

/// A native media app (Music, Spotify, VLC) with an AppleScript dictionary
/// exposing play/pause commands and playback state.
private struct NativeMediaTarget: MediaTarget, Sendable {
    let target: MediaPlaybackTarget
    let bundleID: String
    let appName: String
    let stateCheck: String
    let pauseCommand: String
    let resumeCommand: String

    func pauseBlock() -> String {
        """
        if \(target.rawValue)Running then
            try
                tell application "\(appName)"
                    if \(stateCheck) then
                        \(pauseCommand)
                        set end of pausedTargets to "\(target.rawValue)"
                    end if
                end tell
            end try
        end if
        """
    }

    func resumeBlock() -> String {
        """
        if targetText contains "\(target.rawValue)" then
            try
                tell application "\(appName)" to \(resumeCommand)
            end try
        end if
        """
    }
}

/// A web browser that pauses `<video>`/`<audio>` elements via AppleScript JavaScript.
private struct BrowserTarget: MediaTarget, Sendable {
    let target: MediaPlaybackTarget
    let bundleID: String
    let appName: String
    /// Safari uses `do JavaScript`; Chromium browsers use `execute javascript`.
    let jsVerb: String

    func pauseBlock() -> String {
        let js = BrowserPauseJS.pauseEscaped
        return """
        if \(target.rawValue)Running then
            set didPause\(target.capitalized) to false
            try
                tell application "\(appName)"
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set pauseCount to \(jsVerb) "\(js)" \(jsSuffix)
                                if (pauseCount as integer) > 0 then set didPause\(target.capitalized) to true
                            end try
                        end repeat
                    end repeat
                end tell
            end try
            if didPause\(target.capitalized) then set end of pausedTargets to "\(target.rawValue)"
        end if
        """
    }

    func resumeBlock() -> String {
        let js = BrowserPauseJS.resumeEscaped
        return """
        if targetText contains "\(target.rawValue)" then
            try
                tell application "\(appName)"
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                \(jsVerb) "\(js)" \(jsSuffix)
                            end try
                        end repeat
                    end repeat
                end tell
            end try
        end if
        """
    }

    /// Safari: `do JavaScript "..." in browserTab`.
    /// Chromium: `execute browserTab javascript "..."`.
    private var jsSuffix: String {
        jsVerb == "do JavaScript" ? "in browserTab" : ""
    }
}

private extension MediaPlaybackTarget {
    var capitalized: String {
        rawValue.capitalized
    }
}

/// Shared JS snippet that pauses all playing `<video>`/`<audio>` elements,
/// tagging each so only those elements are resumed later.
private enum BrowserPauseJS {
    static let pause = #"""
    (() => { let n = 0; document.querySelectorAll('video,audio').forEach((m) => { if (!m.paused && !m.ended) { m.dataset.hisohisoPaused = '1'; m.pause(); n += 1; } }); return String(n); })();
    """#

    static let resume = #"""
    (() => { document.querySelectorAll('video[data-hisohiso-paused="1"],audio[data-hisohiso-paused="1"]').forEach((m) => { delete m.dataset.hisohisoPaused; const p = m.play(); if (p && typeof p.catch === 'function') p.catch(() => {}); }); })();
    """#

    /// AppleScript-escaped versions (backslash and double-quote).
    static let pauseEscaped: String = escape(pause)
    static let resumeEscaped: String = escape(resume)

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - All Targets

/// All supported media targets, grouped by type.
private enum MediaTargets {
    static let native: [NativeMediaTarget] = [
        // Ordered for readability; pause order does not matter.
        NativeMediaTarget(
            target: .music, bundleID: "com.apple.Music", appName: "Music",
            stateCheck: "player state is playing", pauseCommand: "pause", resumeCommand: "play"
        ),
        NativeMediaTarget(
            target: .spotify, bundleID: "com.spotify.client", appName: "Spotify",
            stateCheck: "player state is playing", pauseCommand: "pause", resumeCommand: "play"
        ),
        NativeMediaTarget(
            target: .vlc, bundleID: "org.videolan.vlc", appName: "VLC",
            stateCheck: "playing", pauseCommand: "pause", resumeCommand: "play"
        ),
    ]

    static let browsers: [BrowserTarget] = [
        BrowserTarget(target: .safari, bundleID: "com.apple.Safari", appName: "Safari", jsVerb: "do JavaScript"),
        BrowserTarget(target: .chrome, bundleID: "com.google.Chrome", appName: "Google Chrome", jsVerb: "execute browserTab javascript"),
        BrowserTarget(target: .edge, bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", jsVerb: "execute browserTab javascript"),
        BrowserTarget(target: .brave, bundleID: "com.brave.Browser", appName: "Brave Browser", jsVerb: "execute browserTab javascript"),
        BrowserTarget(target: .arc, bundleID: "company.thebrowser.Browser", appName: "Arc", jsVerb: "execute browserTab javascript"),
    ]

    static let all: [any MediaTarget] = native + browsers
}

// MARK: - AppleScript Controller

/// Checks which media apps are running, then generates a minimal AppleScript that
/// only references running apps. This avoids compilation failures when an app
/// (e.g. Edge, Brave, VLC) is not installed — osascript cannot resolve app-specific
/// terminology for apps whose scripting dictionaries it cannot load.
final class AppleScriptMediaPlaybackController: MediaPlaybackControlling {
    private let runner: any AppleScriptRunning
    private let processChecker: any ProcessChecking

    init(
        runner: any AppleScriptRunning = OsaScriptRunner(),
        processChecker: any ProcessChecking = SystemProcessChecker()
    ) {
        self.runner = runner
        self.processChecker = processChecker
    }

    func pausePlayingMedia() async -> Set<MediaPlaybackTarget> {
        let runningTargets = await detectRunningTargets()
        guard !runningTargets.isEmpty else { return [] }

        let script = buildPauseScript(targets: runningTargets)
        let output = await runner.run(script)
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { MediaPlaybackTarget(rawValue: String($0)) }
        )
    }

    func resumeMedia(_ targets: Set<MediaPlaybackTarget>) {
        guard !targets.isEmpty else { return }
        let script = buildResumeScript(targets: targets)
        Task {
            _ = await runner.run(script)
        }
    }

    // MARK: - Process Detection

    /// Returns only the targets whose apps are currently running.
    private func detectRunningTargets() async -> [any MediaTarget] {
        let bundleIDs = MediaTargets.all.map(\.bundleID)
        let runningBundleIDs = await processChecker.runningBundleIDs(from: bundleIDs)

        return MediaTargets.all.filter { runningBundleIDs.contains($0.bundleID) }
    }

    // MARK: - Script Building

    private func buildPauseScript(targets: [any MediaTarget]) -> String {
        var lines: [String] = []
        lines.append("set pausedTargets to {}")
        lines.append("")

        for target in targets {
            lines.append(target.pauseBlock())
            lines.append("")
        }

        // Join the list with newlines for reliable parsing on the Swift side.
        lines.append("set AppleScript's text item delimiters to linefeed")
        lines.append("return pausedTargets as text")
        return lines.joined(separator: "\n")
    }

    private func buildResumeScript(targets: Set<MediaPlaybackTarget>) -> String {
        let targetList = targets.map(\.rawValue).joined(separator: ",")
        var lines: [String] = []
        lines.append(#"set targetText to "\#(targetList)""#)
        lines.append("")

        // Only include blocks for targets we actually paused
        for target in MediaTargets.all where targets.contains(target.target) {
            lines.append(target.resumeBlock())
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Process Checking

@MainActor
protocol ProcessChecking: AnyObject {
    func runningBundleIDs(from candidates: [String]) async -> Set<String>
}

/// Checks running processes via System Events to determine which media apps are active.
final class SystemProcessChecker: ProcessChecking, @unchecked Sendable {
    private let runner: any AppleScriptRunning

    init(runner: any AppleScriptRunning = OsaScriptRunner()) {
        self.runner = runner
    }

    func runningBundleIDs(from candidates: [String]) async -> Set<String> {
        guard !candidates.isEmpty else { return [] }

        // Build a single System Events query that checks all bundle IDs at once.
        // This is always compilable because System Events is always available.
        // We join the result with newlines for reliable parsing.
        let bundleList = candidates.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
        tell application "System Events"
            set checkedIDs to {\(bundleList)}
            set runningIDs to {}
            repeat with bid in checkedIDs
                if exists (processes whose bundle identifier is bid) then
                    set end of runningIDs to bid
                end if
            end repeat
            set AppleScript's text item delimiters to linefeed
            set output to runningIDs as text
            set AppleScript's text item delimiters to ""
            return output
        end tell
        """

        let output = await runner.run(script)
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        )
    }
}

protocol AppleScriptRunning: Sendable {
    func run(_ script: String) async -> String
}

struct OsaScriptRunner: AppleScriptRunning {
    func run(_ script: String) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                if let data = script.data(using: .utf8) {
                    input.fileHandleForWriting.write(data)
                }
                try? input.fileHandleForWriting.close()
                process.waitUntilExit()

                let data = output.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }.value
    }
}
