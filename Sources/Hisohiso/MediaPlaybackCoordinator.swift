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

final class AppleScriptMediaPlaybackController: MediaPlaybackControlling {
    private let runner: any AppleScriptRunning

    init(runner: any AppleScriptRunning = OsaScriptRunner()) {
        self.runner = runner
    }

    func pausePlayingMedia() async -> Set<MediaPlaybackTarget> {
        let output = await runner.run(Self.pauseScript)
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { MediaPlaybackTarget(rawValue: String($0)) }
        )
    }

    func resumeMedia(_ targets: Set<MediaPlaybackTarget>) {
        guard !targets.isEmpty else { return }
        let targetList = targets.map(\.rawValue).joined(separator: ",")
        let script = Self.resumeScript.replacingOccurrences(of: "__TARGETS__", with: targetList)

        Task {
            _ = await runner.run(script)
        }
    }

    private static let pauseScript = """
    set pausedTargets to {}

    tell application "System Events"
        set musicRunning to exists (processes whose bundle identifier is "com.apple.Music")
        set spotifyRunning to exists (processes whose bundle identifier is "com.spotify.client")
        set safariRunning to exists (processes whose bundle identifier is "com.apple.Safari")
        set chromeRunning to exists (processes whose bundle identifier is "com.google.Chrome")
    end tell

    if musicRunning then
        try
            tell application "Music"
                if player state is playing then
                    pause
                    set end of pausedTargets to "music"
                end if
            end tell
        end try
    end if

    if spotifyRunning then
        try
            tell application "Spotify"
                if player state is playing then
                    pause
                    set end of pausedTargets to "spotify"
                end if
            end tell
        end try
    end if

    if safariRunning then
        set didPauseSafari to false
        try
            tell application "Safari"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            set pauseCount to do JavaScript "(() => { let n = 0; document.querySelectorAll('video,audio').forEach((m) => { if (!m.paused && !m.ended) { m.dataset.hisohisoPaused = '1'; m.pause(); n += 1; } }); return String(n); })();" in browserTab
                            if (pauseCount as integer) > 0 then set didPauseSafari to true
                        end try
                    end repeat
                end repeat
            end tell
        end try
        if didPauseSafari then set end of pausedTargets to "safari"
    end if

    if chromeRunning then
        set didPauseChrome to false
        try
            tell application "Google Chrome"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            set pauseCount to execute browserTab javascript "(() => { let n = 0; document.querySelectorAll('video,audio').forEach((m) => { if (!m.paused && !m.ended) { m.dataset.hisohisoPaused = '1'; m.pause(); n += 1; } }); return String(n); })();"
                            if (pauseCount as integer) > 0 then set didPauseChrome to true
                        end try
                    end repeat
                end repeat
            end tell
        end try
        if didPauseChrome then set end of pausedTargets to "chrome"
    end if

    return pausedTargets
    """

    private static let resumeScript = """
    set targetText to "__TARGETS__"

    if targetText contains "music" then
        try
            tell application "Music" to play
        end try
    end if

    if targetText contains "spotify" then
        try
            tell application "Spotify" to play
        end try
    end if

    if targetText contains "safari" then
        try
            tell application "Safari"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            do JavaScript "(() => { document.querySelectorAll('video[data-hisohiso-paused=\"1\"],audio[data-hisohiso-paused=\"1\"]').forEach((m) => { delete m.dataset.hisohisoPaused; const p = m.play(); if (p && typeof p.catch === 'function') p.catch(() => {}); }); })();" in browserTab
                        end try
                    end repeat
                end repeat
            end tell
        end try
    end if

    if targetText contains "chrome" then
        try
            tell application "Google Chrome"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            execute browserTab javascript "(() => { document.querySelectorAll('video[data-hisohiso-paused=\"1\"],audio[data-hisohiso-paused=\"1\"]').forEach((m) => { delete m.dataset.hisohisoPaused; const p = m.play(); if (p && typeof p.catch === 'function') p.catch(() => {}); }); })();"
                        end try
                    end repeat
                end repeat
            end tell
        end try
    end if
    """
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
