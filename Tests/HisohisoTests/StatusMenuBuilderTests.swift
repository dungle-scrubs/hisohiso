import Cocoa
import XCTest
@testable import Hisohiso

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    final class Target: NSObject {
        @objc func selectMicrophone(_ sender: NSMenuItem) {}
        @objc func selectModel(_ sender: NSMenuItem) {}
        @objc func showPreferences() {}
    }

    func testBuildsMicrophoneAndModelSubmenusFromSnapshot() {
        let menu = makeMenu(currentModel: .defaultModel)

        XCTAssertEqual(menu.items.first?.title, "Microphone")
        XCTAssertEqual(menu.items.first?.submenu?.items.first?.state, .on)
        XCTAssertTrue(menu.items.contains { $0.title == "Transcription Model" })
        XCTAssertTrue(menu.items.contains { $0.title == "Preferences..." })
        XCTAssertTrue(menu.items.contains { $0.title == "Quit Hisohiso" })
    }

    func testModelStateUpdatesFromSnapshot() {
        let menu = makeMenu(currentModel: .whisperBase)
        let modelItems = menu.items.first { $0.title == "Transcription Model" }?.submenu?.items ?? []

        XCTAssertEqual(modelItems.first { $0.representedObject as? String == TranscriptionModel.whisperBase.rawValue }?.state, .on)
        XCTAssertEqual(modelItems.first { $0.representedObject as? String == TranscriptionModel.defaultModel.rawValue }?.state, .off)
    }

    func testRecordingStateDoesNotMutateStaticMenuSnapshot() {
        let idleMenu = makeMenu(currentModel: .defaultModel)
        let recordingMenu = makeMenu(currentModel: .defaultModel)

        XCTAssertEqual(idleMenu.items.map(\.title), recordingMenu.items.map(\.title))
    }

    private func makeMenu(currentModel: TranscriptionModel) -> NSMenu {
        let target = Target()
        let coordinator = StatusMenuCoordinator(builder: StatusMenuBuilder(
            target: target,
            selectMicrophone: #selector(Target.selectMicrophone(_:)),
            selectModel: #selector(Target.selectModel(_:)),
            showPreferences: #selector(Target.showPreferences)
        ))
        return coordinator.menu(snapshot: StatusMenuSnapshot(
            microphones: [.systemDefault],
            currentMicrophone: .systemDefault,
            currentModel: currentModel
        ))
    }
}
