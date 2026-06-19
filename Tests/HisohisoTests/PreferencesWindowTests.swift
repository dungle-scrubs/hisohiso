import Cocoa
@testable import Hisohiso
import XCTest

@MainActor
final class PreferencesWindowTests: XCTestCase {
    func testPreferencesWindowShowsInitialTabContent() {
        let window = PreferencesWindow(modelManager: ModelManager())

        let segmentedControl = findSubview(in: window.contentView, matching: NSSegmentedControl.self)
        XCTAssertNotNil(segmentedControl)
        XCTAssertEqual(segmentedControl?.selectedSegment, 0)
        XCTAssertNotNil(findSubview(in: window.contentView, matching: GeneralPreferencesTab.self))
    }

    func testPreferencesWindowSwitchesTabContent() throws {
        let window = PreferencesWindow(modelManager: ModelManager())
        let segmentedControl = try XCTUnwrap(findSubview(in: window.contentView, matching: NSSegmentedControl.self))

        segmentedControl.selectedSegment = 2
        segmentedControl.sendAction(segmentedControl.action, to: segmentedControl.target)

        XCTAssertNil(findSubview(in: window.contentView, matching: GeneralPreferencesTab.self))
        XCTAssertNotNil(findSubview(in: window.contentView, matching: ModelPreferencesTab.self))
    }

    private func findSubview<T: NSView>(in view: NSView?, matching type: T.Type) -> T? {
        guard let view else { return nil }
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = findSubview(in: subview, matching: type) {
                return match
            }
        }
        return nil
    }
}
