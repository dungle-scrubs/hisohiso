@testable import Hisohiso
import XCTest

final class TextFormatterTests: XCTestCase {
    // MARK: - Capitalization

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

    func testCapitalizesAfterExclamation() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("wow! that's amazing"),
            "Wow! That's amazing"
        )
    }

    func testCapitalizesAfterQuestion() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("really? i didn't know"),
            "Really? I didn't know"
        )
    }

    func testPreservesAlreadyCapitalized() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("Hello World"),
            "Hello World"
        )
    }

    // MARK: - Filler Word Removal

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

    func testRemovesMultipleFillers() {
        let formatter = TextFormatter()
        // "like" is no longer a default filler — only um, uh, i mean are
        XCTAssertEqual(
            formatter.format("um uh i mean it works"),
            "It works"
        )
    }

    func testRemovesMultipleFillersWithCustomSet() {
        let formatter = TextFormatter(fillerWords: ["um", "uh", "like", "i mean"])
        XCTAssertEqual(
            formatter.format("um uh like i mean it works"),
            "It works"
        )
    }

    func testFillerWordsCaseInsensitive() {
        let formatter = TextFormatter()
        XCTAssertEqual(
            formatter.format("UM hello UH world"),
            "Hello world"
        )
    }

    func testDoesNotRemovePartialMatches() {
        let formatter = TextFormatter()
        // "umbrella" should not be affected by "um" filter (uses word boundaries)
        XCTAssertEqual(
            formatter.format("umbrella is useful"),
            "Umbrella is useful"
        )
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

    // MARK: - Whitespace Handling

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

    func testHandlesNewlines() {
        let formatter = TextFormatter(removeFillers: false)
        // TextFormatter preserves newlines (only normalizes spaces)
        XCTAssertEqual(
            formatter.format("hello\nworld"),
            "Hello\nworld"
        )
    }

    func testHandlesTabs() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello\tworld"),
            "Hello world"
        )
    }

    // MARK: - Edge Cases

    func testEmptyString() {
        let formatter = TextFormatter()
        XCTAssertEqual(formatter.format(""), "")
    }

    func testWhitespaceOnlyString() {
        let formatter = TextFormatter()
        XCTAssertEqual(formatter.format("   "), "")
    }

    func testSingleWord() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(formatter.format("hello"), "Hello")
    }

    func testSingleCharacter() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(formatter.format("a"), "A")
    }

    func testNumbersAtStart() {
        let formatter = TextFormatter(removeFillers: false)
        // First word after number gets capitalized
        XCTAssertEqual(formatter.format("123 test"), "123 Test")
    }

    func testPunctuationPreserved() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello, world"),
            "Hello, world"
        )
    }

    // MARK: - Multiple Sentences

    func testMultipleSentences() {
        let formatter = TextFormatter(removeFillers: false)
        XCTAssertEqual(
            formatter.format("hello! how are you? i am fine."),
            "Hello! How are you? I am fine."
        )
    }

    func testMultipleSentencesWithFillers() {
        let formatter = TextFormatter()
        // "like" is no longer a default filler
        XCTAssertEqual(
            formatter.format("um hello. uh how are you. er i am fine"),
            "Hello. How are you. I am fine"
        )
    }

    // MARK: - Default Filler Words

    func testDefaultFillerWordsExist() {
        XCTAssertFalse(TextFormatter.defaultFillerWords.isEmpty)
        XCTAssertTrue(TextFormatter.defaultFillerWords.contains("um"))
        XCTAssertTrue(TextFormatter.defaultFillerWords.contains("uh"))
        // "like", "so", "well" etc. were removed from defaults as too aggressive
        XCTAssertFalse(TextFormatter.defaultFillerWords.contains("like"))
        XCTAssertFalse(TextFormatter.defaultFillerWords.contains("so"))
        XCTAssertFalse(TextFormatter.defaultFillerWords.contains("well"))
        XCTAssertFalse(TextFormatter.defaultFillerWords.contains("right"))
        XCTAssertFalse(TextFormatter.defaultFillerWords.contains("actually"))
    }

    // MARK: - Abbreviations & Decimals

    func testPreservesAbbreviations() {
        let formatter = TextFormatter(removeFillers: false)
        // Should NOT capitalize mid-abbreviation (old bug: e.g. → E.G.)
        // Period+space is still treated as sentence boundary (expected)
        XCTAssertEqual(
            formatter.format("e.g. the example"),
            "E.g. The example"
        )
    }

    func testPreservesDecimals() {
        let formatter = TextFormatter(removeFillers: false)
        // Should NOT capitalize after decimal points
        XCTAssertEqual(
            formatter.format("the temperature is 3.5 degrees"),
            "The temperature is 3.5 degrees"
        )
    }

    func testCapitalizesAfterPeriodSpace() {
        let formatter = TextFormatter(removeFillers: false)
        // Should capitalize after period followed by space
        XCTAssertEqual(
            formatter.format("first sentence. second sentence"),
            "First sentence. Second sentence"
        )
    }

    func testCapitalizesAfterEllipsis() {
        let formatter = TextFormatter(removeFillers: false)
        // Ellipsis followed by space should capitalize
        XCTAssertEqual(
            formatter.format("wait... then continue"),
            "Wait... Then continue"
        )
    }

    // MARK: - Real-World Examples

    func testRealWorldDictation() {
        let formatter = TextFormatter()
        // Default fillers: um, uh, er, ah, you know, i mean, kind of, sort of
        // "so" and "basically" are NOT default fillers (too aggressive)
        XCTAssertEqual(
            formatter.format("um so basically i think we should um schedule a meeting you know"),
            "So basically i think we should schedule a meeting"
        )
    }

    func testRealWorldDictationWithCustomFillers() {
        // Users can still add aggressive fillers via preferences
        let formatter = TextFormatter(fillerWords: ["um", "uh", "so", "basically", "you know"])
        XCTAssertEqual(
            formatter.format("um so basically i think we should um schedule a meeting you know"),
            "I think we should schedule a meeting"
        )
    }

    func testRealWorldWithPunctuation() {
        let formatter = TextFormatter()
        XCTAssertEqual(
            formatter.format("um hello. uh i wanted to ask you know about the project"),
            "Hello. I wanted to ask about the project"
        )
    }
}
