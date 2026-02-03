import Foundation

/// Formats transcribed text with smart capitalization, punctuation, and filler word removal
struct TextFormatter {
    /// Default filler words to remove
    static let defaultFillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "you know", "i mean",
        "basically", "actually", "literally", "so", "well",
        "kind of", "sort of", "right"
    ]

    private let fillerWords: Set<String>
    private let removeFillers: Bool
    private let capitalizeFirst: Bool
    private let capitalizeSentences: Bool

    /// Initialize the text formatter
    /// - Parameters:
    ///   - fillerWords: Words to remove (default: from UserDefaults or common filler words)
    ///   - removeFillers: Whether to remove filler words (default: true)
    ///   - capitalizeFirst: Capitalize first character (default: true)
    ///   - capitalizeSentences: Capitalize after sentence-ending punctuation (default: true)
    init(
        fillerWords: Set<String>? = nil,
        removeFillers: Bool = true,
        capitalizeFirst: Bool = true,
        capitalizeSentences: Bool = true
    ) {
        // Load from UserDefaults if not provided
        if let fillerWords {
            self.fillerWords = fillerWords
        } else if let saved = UserDefaults.standard.stringArray(forKey: "fillerWords") {
            self.fillerWords = Set(saved)
        } else {
            self.fillerWords = Self.defaultFillerWords
        }
        self.removeFillers = removeFillers
        self.capitalizeFirst = capitalizeFirst
        self.capitalizeSentences = capitalizeSentences
    }

    /// Format the transcribed text
    /// - Parameter text: Raw transcription output
    /// - Returns: Formatted text ready for insertion
    func format(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove filler words
        if removeFillers {
            result = removeFillerWords(from: result)
        }

        // Clean up whitespace
        result = normalizeWhitespace(result)

        // Capitalize
        if capitalizeFirst || capitalizeSentences {
            result = applyCaps(to: result)
        }

        return result
    }

    // MARK: - Private Helpers

    private func removeFillerWords(from text: String) -> String {
        var result = text.lowercased()

        // Sort by length descending to match longer phrases first
        let sortedFillers = fillerWords.sorted { $0.count > $1.count }

        for filler in sortedFillers {
            // Use word boundary \b to avoid partial matches (e.g., "um" in "umbrella")
            let escapedFiller = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "\\b" + escapedFiller + "\\b\\s*,?\\s*"

            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        return result
    }

    private func normalizeWhitespace(_ text: String) -> String {
        // Replace multiple spaces with single space
        let components = text.components(separatedBy: .whitespaces)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func applyCaps(to text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text
        var shouldCapitalize = capitalizeFirst

        var chars = Array(result)
        for i in 0 ..< chars.count {
            if shouldCapitalize, chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                shouldCapitalize = false
            }

            // Check for sentence-ending punctuation
            if capitalizeSentences, [".", "!", "?"].contains(String(chars[i])) {
                shouldCapitalize = true
            }
        }

        return String(chars)
    }
}
