import Carbon.HIToolbox
@testable import Hisohiso
import XCTest

final class HistoryHotkeyMonitorTests: XCTestCase {
    /// Unique suite name per test run to avoid polluting real UserDefaults.
    private let suiteName = "com.hisohiso.tests.history-hotkey-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Default Hotkey

    func testDefaultHotkeyIsCtrlOptionSpace() {
        let monitor = HistoryHotkeyMonitor(defaults: defaults)

        XCTAssertEqual(monitor.currentHotkey, KeyCombo.ctrlOptionSpace)
    }

    // MARK: - Load Saved Hotkey

    func testLoadsSavedHotkeyFromDefaults() throws {
        let custom = KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | shiftKey))
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, for: .historyHotkey)

        let monitor = HistoryHotkeyMonitor(defaults: defaults)

        XCTAssertEqual(monitor.currentHotkey, custom)
    }

    // MARK: - setHotkey Persistence

    func testSetHotkeyPersistsToDefaults() throws {
        let monitor = HistoryHotkeyMonitor(defaults: defaults)
        let custom = KeyCombo.cmdShiftSpace

        monitor.setHotkey(custom)

        // Verify it's persisted
        let data = try XCTUnwrap(defaults.data(for: .historyHotkey))
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(decoded, custom)
        // Verify in-memory state matches
        XCTAssertEqual(monitor.currentHotkey, custom)
    }

    func testSetHotkeyNilClearsPersistence() {
        let monitor = HistoryHotkeyMonitor(defaults: defaults)

        // First set something
        monitor.setHotkey(KeyCombo.cmdShiftSpace)
        XCTAssertNotNil(defaults.data(for: .historyHotkey))

        // Then clear
        monitor.setHotkey(nil)

        XCTAssertNil(monitor.currentHotkey)
        XCTAssertNil(defaults.data(for: .historyHotkey))
    }

    // MARK: - Display String

    func testDisplayStringReflectsCurrentHotkey() {
        let monitor = HistoryHotkeyMonitor(defaults: defaults)
        XCTAssertEqual(monitor.displayString, "⌃⌥Space")

        monitor.setHotkey(KeyCombo.cmdShiftSpace)
        XCTAssertEqual(monitor.displayString, "⇧⌘Space")

        monitor.setHotkey(nil)
        XCTAssertEqual(monitor.displayString, "Disabled")
    }
}
