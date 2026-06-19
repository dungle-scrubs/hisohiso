@testable import Hisohiso
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
}

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
