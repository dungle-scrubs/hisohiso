import Foundation
import SwiftData

// MARK: - TranscriptionRecord Model

/// A single transcription record stored in history
@Model
final class TranscriptionRecord {
    /// Unique identifier
    var id: UUID

    /// The transcribed text
    var text: String

    /// When the transcription was created
    var timestamp: Date

    /// Duration of the audio recording in seconds
    var duration: TimeInterval

    /// Model used for transcription
    var modelName: String

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        duration: TimeInterval,
        modelName: String
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.modelName = modelName
    }
}

// MARK: - HistoryStore

/// Manages transcription history persistence with SwiftData
@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private static let schema = Schema([TranscriptionRecord.self])

    private let container: ModelContainer?
    private let context: ModelContext?

    /// Creates a HistoryStore.
    /// - Parameters:
    ///   - inMemory: Whether to store data in memory only.
    ///   - modelName: SwiftData model container name.
    private init(inMemory: Bool = false, modelName: String = "Hisohiso") {
        do {
            let config = ModelConfiguration(
                modelName,
                schema: Self.schema,
                isStoredInMemoryOnly: inMemory
            )
            let container = try ModelContainer(for: Self.schema, configurations: [config])
            self.container = container
            context = container.mainContext
            logInfo("HistoryStore initialized (inMemory: \(inMemory))")
        } catch {
            container = nil
            context = nil
            logError("Failed to initialize HistoryStore: \(error)")
        }
    }

    /// Creates an isolated in-memory store for unit tests.
    /// - Returns: A new HistoryStore backed by in-memory SwiftData.
    static func makeInMemoryForTesting() -> HistoryStore {
        HistoryStore(inMemory: true, modelName: "HisohisoTests-\(UUID().uuidString)")
    }

    // MARK: - CRUD Operations

    /// Save a new transcription to history
    /// - Parameters:
    ///   - text: The transcribed text
    ///   - duration: Recording duration in seconds
    ///   - modelName: Name of the model used
    /// - Returns: The saved record, or nil if save failed
    @discardableResult
    func save(text: String, duration: TimeInterval, modelName: String) -> TranscriptionRecord? {
        guard let context else {
            logError("HistoryStore: No context available")
            return nil
        }

        let record = TranscriptionRecord(
            text: text,
            duration: duration,
            modelName: modelName
        )

        context.insert(record)

        do {
            try context.save()
            logInfo("Saved transcription to history: \(text.prefix(50))...")
            return record
        } catch {
            logError("Failed to save transcription: \(error)")
            return nil
        }
    }

    /// Fetch recent transcriptions
    /// - Parameter limit: Maximum number of records to return
    /// - Returns: Array of transcription records, newest first
    func recent(limit: Int = 50) -> [TranscriptionRecord] {
        guard let context else { return [] }

        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            logError("Failed to fetch recent transcriptions: \(error)")
            return []
        }
    }

    /// Search transcriptions with fuzzy matching
    /// - Parameter query: Search query string
    /// - Returns: Matching transcription records, ranked by relevance
    func search(query: String) -> [TranscriptionRecord] {
        guard let context else { return [] }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return recent(limit: 50)
        }

        let lowercasedQuery = query.lowercased()

        // Fetch all and filter in memory for fuzzy matching
        // SwiftData predicates don't support fuzzy search well
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500 // Reasonable upper bound

        do {
            let allRecords = try context.fetch(descriptor)
            return allRecords
                .map { record -> (record: TranscriptionRecord, score: Int) in
                    let score = fuzzyMatchScore(text: record.text.lowercased(), query: lowercasedQuery)
                    return (record, score)
                }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }
                .prefix(50)
                .map(\.record)
        } catch {
            logError("Failed to search transcriptions: \(error)")
            return []
        }
    }

    /// Delete a specific record
    /// - Parameter record: The record to delete
    func delete(_ record: TranscriptionRecord) {
        guard let context else { return }

        context.delete(record)

        do {
            try context.save()
            logInfo("Deleted transcription from history")
        } catch {
            logError("Failed to delete transcription: \(error)")
        }
    }

    /// Delete all history
    func deleteAll() {
        guard let context else { return }

        do {
            try context.delete(model: TranscriptionRecord.self)
            try context.save()
            logInfo("Deleted all transcription history")
        } catch {
            logError("Failed to delete all transcriptions: \(error)")
        }
    }

    /// Total count of transcriptions
    var count: Int {
        guard let context else { return 0 }

        let descriptor = FetchDescriptor<TranscriptionRecord>()

        do {
            return try context.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    // MARK: - Fuzzy Matching

    /// Calculate fuzzy match score between text and query
    /// Higher score = better match
    private func fuzzyMatchScore(text: String, query: String) -> Int {
        // Exact substring match gets highest score
        if text.contains(query) {
            return 1000 + (100 - min(text.count, 100)) // Shorter text ranks higher
        }

        // Word-based matching
        let queryWords = query.split(separator: " ").map(String.init)
        let textWords = Set(text.split(separator: " ").map { String($0).lowercased() })

        var score = 0

        for queryWord in queryWords {
            // Exact word match
            if textWords.contains(queryWord) {
                score += 100
                continue
            }

            // Prefix match on any word
            for textWord in textWords where textWord.hasPrefix(queryWord) {
                score += 50
                break
            }

            // Subsequence match (characters appear in order)
            if isSubsequence(queryWord, of: text) {
                score += 25
            }
        }

        return score
    }

    /// Check if query characters appear in order within text
    private func isSubsequence(_ query: String, of text: String) -> Bool {
        var queryIndex = query.startIndex

        for char in text {
            if queryIndex < query.endIndex && char == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }

        return queryIndex == query.endIndex
    }
}
