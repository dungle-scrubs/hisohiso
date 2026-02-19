import XCTest
@testable import Hisohiso

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var store: HistoryStore!

    override func setUp() async throws {
        // Use isolated in-memory storage to avoid touching user history.
        store = HistoryStore.makeInMemoryForTesting()
        store.deleteAll()
    }

    override func tearDown() async throws {
        store.deleteAll()
    }

    // MARK: - Basic CRUD

    func testSaveAndRetrieve() async throws {
        let record = store.save(text: "Hello world", duration: 2.5, modelName: "test-model")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.text, "Hello world")
        XCTAssertEqual(record?.duration, 2.5)
        XCTAssertEqual(record?.modelName, "test-model")

        let recent = store.recent(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.text, "Hello world")
    }

    func testRecentOrdersNewestFirst() async throws {
        store.save(text: "First", duration: 1.0, modelName: "test")
        // Small delay to ensure different timestamps
        try await Task.sleep(for: .milliseconds(10))
        store.save(text: "Second", duration: 1.0, modelName: "test")
        try await Task.sleep(for: .milliseconds(10))
        store.save(text: "Third", duration: 1.0, modelName: "test")

        let recent = store.recent(limit: 10)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].text, "Third")
        XCTAssertEqual(recent[1].text, "Second")
        XCTAssertEqual(recent[2].text, "First")
    }

    func testRecentRespectsLimit() async throws {
        for i in 1 ... 10 {
            store.save(text: "Item \(i)", duration: 1.0, modelName: "test")
        }

        let recent = store.recent(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }

    func testDeleteRecord() async throws {
        let record = store.save(text: "To delete", duration: 1.0, modelName: "test")
        XCTAssertNotNil(record)
        XCTAssertEqual(store.count, 1)

        store.delete(record!)
        XCTAssertEqual(store.count, 0)
    }

    func testDeleteAll() async throws {
        store.save(text: "One", duration: 1.0, modelName: "test")
        store.save(text: "Two", duration: 1.0, modelName: "test")
        store.save(text: "Three", duration: 1.0, modelName: "test")
        XCTAssertEqual(store.count, 3)

        store.deleteAll()
        XCTAssertEqual(store.count, 0)
    }

    // MARK: - Search

    func testSearchExactMatch() async throws {
        store.save(text: "The quick brown fox", duration: 1.0, modelName: "test")
        store.save(text: "Lazy dog", duration: 1.0, modelName: "test")

        let results = store.search(query: "quick")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "The quick brown fox")
    }

    func testSearchCaseInsensitive() async throws {
        store.save(text: "Hello World", duration: 1.0, modelName: "test")

        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)

        let results2 = store.search(query: "WORLD")
        XCTAssertEqual(results2.count, 1)
    }

    func testSearchMultipleWords() async throws {
        store.save(text: "Meeting with John about project", duration: 1.0, modelName: "test")
        store.save(text: "Call John tomorrow", duration: 1.0, modelName: "test")
        store.save(text: "Project deadline Friday", duration: 1.0, modelName: "test")

        let results = store.search(query: "John project")
        // Should find the one with both words first
        XCTAssertTrue(results.count >= 1)
        XCTAssertTrue(results[0].text.contains("John"))
    }

    func testSearchEmptyQueryReturnsRecent() async throws {
        store.save(text: "Item one", duration: 1.0, modelName: "test")
        store.save(text: "Item two", duration: 1.0, modelName: "test")

        let results = store.search(query: "")
        XCTAssertEqual(results.count, 2)

        let results2 = store.search(query: "   ")
        XCTAssertEqual(results2.count, 2)
    }

    func testSearchNoResults() async throws {
        store.save(text: "Hello world", duration: 1.0, modelName: "test")

        let results = store.search(query: "xyz123")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Edge Cases

    func testSaveEmptyText() async throws {
        let record = store.save(text: "", duration: 1.0, modelName: "test")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.text, "")
    }

    func testSaveVeryLongText() async throws {
        let longText = String(repeating: "a", count: 10000)
        let record = store.save(text: longText, duration: 1.0, modelName: "test")
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.text.count, 10000)
    }

    func testCount() async throws {
        XCTAssertEqual(store.count, 0)

        store.save(text: "One", duration: 1.0, modelName: "test")
        XCTAssertEqual(store.count, 1)

        store.save(text: "Two", duration: 1.0, modelName: "test")
        XCTAssertEqual(store.count, 2)
    }
}
