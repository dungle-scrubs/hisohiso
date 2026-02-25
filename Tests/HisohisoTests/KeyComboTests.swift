import Carbon.HIToolbox
@testable import Hisohiso
import XCTest

final class KeyComboTests: XCTestCase {
    // MARK: - Initialization

    func testInitWithRawValues() {
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

        XCTAssertEqual(combo.keyCode, UInt32(kVK_Space))
        XCTAssertTrue(combo.hasCommand)
        XCTAssertTrue(combo.hasShift)
        XCTAssertFalse(combo.hasOption)
        XCTAssertFalse(combo.hasControl)
    }

    func testPresets() {
        XCTAssertTrue(KeyCombo.cmdShiftSpace.hasCommand)
        XCTAssertTrue(KeyCombo.cmdShiftSpace.hasShift)
        XCTAssertFalse(KeyCombo.cmdShiftSpace.hasOption)
        XCTAssertEqual(KeyCombo.cmdShiftSpace.keyCode, UInt32(kVK_Space))

        XCTAssertTrue(KeyCombo.ctrlOptionSpace.hasControl)
        XCTAssertTrue(KeyCombo.ctrlOptionSpace.hasOption)
        XCTAssertFalse(KeyCombo.ctrlOptionSpace.hasCommand)
        XCTAssertEqual(KeyCombo.ctrlOptionSpace.keyCode, UInt32(kVK_Space))
    }

    // MARK: - Display String

    func testDisplayStringSpace() {
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        XCTAssertEqual(combo.displayString, "⌘Space")
    }

    func testDisplayStringMultipleModifiers() {
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        // Order should be: ⌃⌥⇧⌘
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘Space")
    }

    func testDisplayStringFunctionKeys() {
        let f1 = KeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0)
        XCTAssertEqual(f1.displayString, "F1")

        let f12 = KeyCombo(keyCode: UInt32(kVK_F12), modifiers: UInt32(cmdKey))
        XCTAssertEqual(f12.displayString, "⌘F12")
    }

    func testDisplayStringArrowKeys() {
        let up = KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey))
        XCTAssertEqual(up.displayString, "⌥↑")

        let down = KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey))
        XCTAssertEqual(down.displayString, "⌘↓")
    }

    func testDisplayStringSpecialKeys() {
        let returnKey = KeyCombo(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey))
        XCTAssertEqual(returnKey.displayString, "⌘↵")

        let escape = KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)
        XCTAssertEqual(escape.displayString, "⎋")

        let tab = KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey))
        XCTAssertEqual(tab.displayString, "⌘⇥")
    }

    // MARK: - Equality

    func testEquality() {
        let combo1 = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        let combo2 = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        XCTAssertEqual(combo1, combo2)
    }

    func testInequalityKeyCode() {
        let combo1 = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        let combo2 = KeyCombo(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey))
        XCTAssertNotEqual(combo1, combo2)
    }

    func testInequalityModifiers() {
        let combo1 = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        let combo2 = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        XCTAssertNotEqual(combo1, combo2)
    }

    // MARK: - Codable

    func testEncodeDecode() throws {
        let original = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KeyCombo.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.keyCode, decoded.keyCode)
        XCTAssertEqual(original.modifiers, decoded.modifiers)
    }

    // MARK: - Modifier Checks

    func testHasCommand() {
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey)).hasCommand)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: UInt32(optionKey)).hasCommand)
    }

    func testHasOption() {
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: UInt32(optionKey)).hasOption)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey)).hasOption)
    }

    func testHasControl() {
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: UInt32(controlKey)).hasControl)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey)).hasControl)
    }

    func testHasShift() {
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: UInt32(shiftKey)).hasShift)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey)).hasShift)
    }
}
