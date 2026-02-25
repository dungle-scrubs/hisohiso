import Foundation

/// Formats transcribed text with smart capitalization, punctuation, and filler word removal
struct TextFormatter {
    /// Default filler words to remove.
    /// Only includes words/phrases that are almost never intentional in dictation.
    /// Common words like "so", "well", "right", "actually" are excluded because
    /// they frequently appear in legitimate speech.
    static let defaultFillerWords: Set<String> = [
        "um", "uh", "er", "ah", "you know", "i mean",
        "kind of", "sort of",
    ]

    private let removeFillers: Bool
    private let capitalizeFirst: Bool
    private let capitalizeSentences: Bool

    /// Precompiled regexes for filler word removal, sorted longest-first.
    private let fillerRegexes: [(pattern: NSRegularExpression, filler: String)]

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
        let words: Set<String> = if let fillerWords {
            fillerWords
        } else if let saved = UserDefaults.standard.stringArray(for: .fillerWords) {
            Set(saved)
        } else {
            Self.defaultFillerWords
        }

        self.removeFillers = removeFillers
        self.capitalizeFirst = capitalizeFirst
        self.capitalizeSentences = capitalizeSentences

        // Precompile regexes sorted by length descending (match longer phrases first)
        fillerRegexes = words
            .sorted { $0.count > $1.count }
            .compactMap { filler in
                let escaped = NSRegularExpression.escapedPattern(for: filler)
                let pattern = "\\b" + escaped + "\\b\\s*,?\\s*"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    return nil
                }
                return (regex, filler)
            }
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
        var result = text

        for (regex, _) in fillerRegexes {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
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

        var chars = Array(text)
        var shouldCapitalize = capitalizeFirst
        // Track if we just saw sentence-ending punctuation and are scanning for whitespace.
        var pendingCapitalize = false

        for i in 0..<chars.count {
            if shouldCapitalize, chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                shouldCapitalize = false
                pendingCapitalize = false
            }

            if capitalizeSentences {
                if [".", "!", "?"].contains(String(chars[i])) {
                    // Don't capitalize yet — wait for whitespace to confirm sentence boundary
                    pendingCapitalize = true
                } else if pendingCapitalize, chars[i].isWhitespace {
                    shouldCapitalize = true
                    pendingCapitalize = false
                } else if pendingCapitalize, !chars[i].isWhitespace, chars[i] != ".", chars[i] != "!", chars[i] != "?" {
                    // Non-whitespace after punctuation (e.g., "3.5", "e.g.") — not a sentence boundary
                    pendingCapitalize = false
                }
            }
        }

        return String(chars)
    }
}
