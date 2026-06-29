@testable import Hisohiso
import os
import XCTest

@MainActor
final class MediaPlaybackCoordinatorTests: XCTestCase {
    func testPauseDoesNothingWhenNothingIsPlaying() async {
        let controller = SpyMediaPlaybackController(pauseResult: [])
        let coordinator = MediaPlaybackCoordinator(controller: controller)

        await coordinator.pauseForRecording()
        coordinator.resumeAfterRecording()

        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertTrue(controller.resumedTargets.isEmpty)
    }

    func testPauseAndResumeOnlyPreviouslyPausedTargets() async {
        let controller = SpyMediaPlaybackController(pauseResult: [.music, .chrome])
        let coordinator = MediaPlaybackCoordinator(controller: controller)

        await coordinator.pauseForRecording()
        coordinator.resumeAfterRecording()

        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertEqual(controller.resumedTargets, [.music, .chrome])
    }

    func testRepeatedPauseDuringSameRecordingDoesNotPauseAgain() async {
        let controller = SpyMediaPlaybackController(pauseResult: [.spotify])
        let coordinator = MediaPlaybackCoordinator(controller: controller)

        await coordinator.pauseForRecording()
        await coordinator.pauseForRecording()

        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertTrue(controller.resumedTargets.isEmpty)
    }

    // MARK: - New Targets

    func testPauseAndResumeNewBrowserTargets() async {
        let controller = SpyMediaPlaybackController(pauseResult: [.edge, .brave, .arc])
        let coordinator = MediaPlaybackCoordinator(controller: controller)

        await coordinator.pauseForRecording()
        coordinator.resumeAfterRecording()

        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertEqual(controller.resumedTargets, [.edge, .brave, .arc])
    }

    func testPauseAndResumeVLCTarget() async {
        let controller = SpyMediaPlaybackController(pauseResult: [.vlc])
        let coordinator = MediaPlaybackCoordinator(controller: controller)

        await coordinator.pauseForRecording()
        coordinator.resumeAfterRecording()

        XCTAssertEqual(controller.resumedTargets, [.vlc])
    }

    func testAllTargetsAreCovered() {
        // Ensure all expected targets exist so script generation includes them.
        let allTargets: Set<MediaPlaybackTarget> = [
            .music, .spotify, .safari, .chrome, .edge, .brave, .arc, .vlc,
        ]
        XCTAssertEqual(Set(MediaPlaybackTarget.allCases), allTargets)
    }
}

// MARK: - AppleScript Controller Tests

@MainActor
final class AppleScriptMediaPlaybackControllerTests: XCTestCase {
    func testPauseOnlyIncludesRunningAppsInScript() async {
        // Only Music is "running"
        let checker = StubProcessChecker(runningBundleIDs: ["com.apple.Music"])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        _ = await controller.pausePlayingMedia()

        let script = runner.lastScript
        XCTAssertNotNil(script)
        // Script should include Music block
        XCTAssertTrue(script?.contains(#"tell application "Music""#) ?? false)
        // Script should NOT include apps that aren't running
        XCTAssertFalse(script?.contains(#"tell application "Spotify""#) ?? true)
        XCTAssertFalse(script?.contains(#"tell application "Microsoft Edge""#) ?? true)
        XCTAssertFalse(script?.contains(#"tell application "VLC""#) ?? true)
    }

    func testPauseIncludesMultipleRunningBrowsers() async {
        let checker = StubProcessChecker(runningBundleIDs: [
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "com.google.Chrome",
        ])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        _ = await controller.pausePlayingMedia()

        let script = runner.lastScript ?? ""
        XCTAssertTrue(script.contains(#"tell application "Safari""#))
        XCTAssertTrue(script.contains(#"tell application "Google Chrome""#))
        XCTAssertTrue(script.contains(#"tell application "Arc""#))
        // Should not include non-running apps
        XCTAssertFalse(script.contains(#"tell application "Music""#))
        XCTAssertFalse(script.contains(#"tell application "Spotify""#))
        XCTAssertFalse(script.contains(#"tell application "Microsoft Edge""#))
        XCTAssertFalse(script.contains(#"tell application "Brave Browser""#))
    }

    func testPauseReturnsEmptyWhenNothingRunning() async {
        let checker = StubProcessChecker(runningBundleIDs: [])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        let result = await controller.pausePlayingMedia()

        XCTAssertTrue(result.isEmpty)
        // Should not even run a script
        XCTAssertNil(runner.lastScript)
    }

    func testResumeOnlyIncludesPreviouslyPausedTargets() async {
        let checker = StubProcessChecker(runningBundleIDs: [])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        controller.resumeMedia([.music, .arc])
        // resumeMedia dispatches the script asynchronously via Task
        await runner.waitForScript()

        let script = runner.lastScript ?? ""
        XCTAssertTrue(script.contains(#"tell application "Music" to play"#))
        XCTAssertTrue(script.contains(#"tell application "Arc""#))
        // Should not include targets that weren't paused
        XCTAssertFalse(script.contains(#"tell application "Spotify""#))
        XCTAssertFalse(script.contains(#"tell application "Google Chrome""#))
    }

    func testResumeIncludesVLC() async {
        let checker = StubProcessChecker(runningBundleIDs: [])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        controller.resumeMedia([.vlc])
        await runner.waitForScript()

        let script = runner.lastScript ?? ""
        XCTAssertTrue(script.contains(#"tell application "VLC" to play"#))
    }

    func testChromiumPauseBlockUsesExecuteJavascript() async {
        let checker = StubProcessChecker(runningBundleIDs: ["com.brave.Browser"])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        _ = await controller.pausePlayingMedia()

        let script = runner.lastScript ?? ""
        XCTAssertTrue(script.contains("execute browserTab javascript"))
    }

    func testSafariPauseBlockUsesDoJavaScript() async {
        let checker = StubProcessChecker(runningBundleIDs: ["com.apple.Safari"])
        let runner = CapturingScriptRunner()
        let controller = AppleScriptMediaPlaybackController(
            runner: runner,
            processChecker: checker
        )

        _ = await controller.pausePlayingMedia()

        let script = runner.lastScript ?? ""
        XCTAssertTrue(script.contains("do JavaScript"))
        XCTAssertFalse(script.contains("execute browserTab javascript"))
    }
}

// MARK: - Preference Tests

@MainActor
final class MediaPausePreferenceTests: XCTestCase {
    func testPauseMediaDefaultsToTrue() {
        let defaults = makeDefaults()
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertTrue(prefs.pauseMediaDuringRecording)
    }

    func testPauseMediaCanBeDisabled() {
        let defaults = makeDefaults()
        defaults.set(false, for: .pauseMediaDuringRecording)
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertFalse(prefs.pauseMediaDuringRecording)
    }

    func testPauseMediaCanBeEnabled() {
        let defaults = makeDefaults()
        defaults.set(false, for: .pauseMediaDuringRecording)
        defaults.set(true, for: .pauseMediaDuringRecording)
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertTrue(prefs.pauseMediaDuringRecording)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "com.hisohiso.tests.media-pause-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }
}

// MARK: - Test Doubles

private final class SpyMediaPlaybackController: MediaPlaybackControlling {
    let pauseResult: Set<MediaPlaybackTarget>
    private(set) var pauseCount = 0
    private(set) var resumedTargets = Set<MediaPlaybackTarget>()

    init(pauseResult: Set<MediaPlaybackTarget>) {
        self.pauseResult = pauseResult
    }

    func pausePlayingMedia() async -> Set<MediaPlaybackTarget> {
        pauseCount += 1
        return pauseResult
    }

    func resumeMedia(_ targets: Set<MediaPlaybackTarget>) {
        resumedTargets = targets
    }
}

private final class StubProcessChecker: ProcessChecking {
    let runningBundleIDs: Set<String>

    init(runningBundleIDs: Set<String>) {
        self.runningBundleIDs = runningBundleIDs
    }

    func runningBundleIDs(from candidates: [String]) async -> Set<String> {
        runningBundleIDs.intersection(candidates)
    }
}

private final class CapturingScriptRunner: AppleScriptRunning {
    private let lock = OSAllocatedUnfairLock<Box<String?>>(initialState: Box(nil))

    var lastScript: String? {
        lock.withLock { $0.value }
    }

    func run(_ script: String) async -> String {
        lock.withLock { $0.value = script }
        return ""
    }

    /// Wait for a script to be captured (up to ~2s).
    func waitForScript(timeoutNanos: UInt64 = 2_000_000_000) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanos
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if lastScript != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
