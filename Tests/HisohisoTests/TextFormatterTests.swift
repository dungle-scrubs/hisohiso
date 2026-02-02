import XCTest
@testable import Hisohiso

final class TextFormatterTests: XCTestCase {
    func testCapitalizesFirstCharacter() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(formatter.format("hello world"), "Hello world")
    }

    func testCapitalizesSentences() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello. world. test"),
            "Hello. World. Test"
        )
    }

    func testRemovesFillerWords() {
        let formatter = TextFormatter()
        XCTAssertEqual(
            formatter.format("um i think it works"),
            "I think it works"
        )
    }

    func testRemovesFillerWordsInMiddle() {
        let formatter = TextFormatter()
        XCTAssertEqual(
            formatter.format("i think um it works"),
            "I think it works"
        )
    }

    func testRemovesFillerWordsAtEnd() {
        let formatter = TextFormatter()
        XCTAssertEqual(
            formatter.format("it works you know"),
            "It works"
        )
    }

    func testNormalizesWhitespace() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello    world"),
            "Hello world"
        )
    }

    func testTrimsWhitespace() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("  hello world  "),
            "Hello world"
        )
    }

    func testEmptyString() {
        let formatter = TextFormatter()
        XCTAssertEqual(formatter.format(""), "")
    }

    func testCustomFillerWords() {
        let formatter = TextFormatter(fillerWords: ["foo", "bar"])
        XCTAssertEqual(
            formatter.format("foo test bar"),
            "Test"
        )
    }

    func testDisableFillerRemoval() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("um hello"),
            "Um hello"
        )
    }

    func testMultipleSentences() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello! how are you? i am fine."),
            "Hello! How are you? I am fine."
        )
    }
}
