@testable import Hisohiso
import AppKit
import XCTest

/// Tests for TextInserter's pasteboard snapshot/restore round-tripping.
///
/// These exercise the injectable-pasteboard seam added in Phase 1 so the
/// snapshot/restore path can be verified without touching the user's real
/// clipboard. Every test allocates its own uniquely named NSPasteboard and
/// releases it, so runs are deterministic and isolated from `.general`.
final class TextInserterTests: XCTestCase {
    // MARK: - Fixtures

    private static let customType = NSPasteboard.PasteboardType("com.hisohiso.tests.custom")
    private static let rtfType = NSPasteboard.PasteboardType("public.rtf")

    /// Create a private, uniquely named pasteboard that shares nothing with
    /// `.general`. The caller is responsible for releasing it (see `defer`).
    private func makeIsolatedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.hisohiso.tests.\(UUID().uuidString)"))
    }

    // MARK: - String round-trip

    func testSnapshotRestoreRoundTripsPlainString() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("original clipboard text", forType: .string))

        let snapshot = TextInserter.snapshotPasteboard(pasteboard)

        // Clobber the pasteboard the way a paste operation would.
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("dictated replacement", forType: .string))
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated replacement")

        TextInserter.restorePasteboard(snapshot, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard text")
    }

    func testSnapshotRestorePreservesUnicodeString() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        let original = "héllo 🌸 ひそひそ — line\nbreak\ttab"
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(original, forType: .string))

        let snapshot = TextInserter.snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("scratch", forType: .string))

        TextInserter.restorePasteboard(snapshot, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), original)
    }

    // MARK: - Multi-type round-trip

    func testSnapshotRestoreRoundTripsMultiTypeItem() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        let stringValue = "styled text"
        let rtfData = Data("{\\rtf1 styled text}".utf8)
        let customData = Data([0x00, 0x01, 0xFE, 0xFF, 0x42])

        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString(stringValue, forType: .string))
        XCTAssertTrue(item.setData(rtfData, forType: Self.rtfType))
        XCTAssertTrue(item.setData(customData, forType: Self.customType))

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = TextInserter.snapshotPasteboard(pasteboard)

        // Overwrite with a single plain-string item to prove restore rebuilds
        // every type, not just the string.
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("clobbered", forType: .string))

        TextInserter.restorePasteboard(snapshot, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), stringValue)
        XCTAssertEqual(pasteboard.data(forType: Self.rtfType), rtfData)
        XCTAssertEqual(pasteboard.data(forType: Self.customType), customData)
    }

    func testSnapshotRestoreRoundTripsMultipleItems() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        let firstItem = NSPasteboardItem()
        XCTAssertTrue(firstItem.setString("first", forType: .string))
        let secondItem = NSPasteboardItem()
        XCTAssertTrue(secondItem.setData(Data([0xAA, 0xBB]), forType: Self.customType))

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([firstItem, secondItem]))

        // A snapshot taken before any mutation is the source of truth.
        let snapshot = TextInserter.snapshotPasteboard(pasteboard)
        XCTAssertEqual(snapshot.count, 2)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("clobbered", forType: .string))

        TextInserter.restorePasteboard(snapshot, to: pasteboard)

        // A fresh snapshot after restore must equal the original snapshot,
        // proving item count, ordering, types, and bytes all round-trip.
        let restored = TextInserter.snapshotPasteboard(pasteboard)
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - Empty snapshot

    func testSnapshotOfEmptyPasteboardIsEmpty() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()

        XCTAssertTrue(TextInserter.snapshotPasteboard(pasteboard).isEmpty)
    }

    func testRestoreEmptySnapshotClearsPasteboard() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("leftover", forType: .string))

        TextInserter.restorePasteboard([], to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue((pasteboard.pasteboardItems ?? []).isEmpty)
    }

    // MARK: - changeCount guard

    /// When nothing external mutates the pasteboard, its changeCount is stable,
    /// so the production restore guard passes and the snapshot is restored.
    func testUnchangedChangeCountAllowsRestore() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("user original", forType: .string))
        let snapshot = TextInserter.snapshotPasteboard(pasteboard)

        // Simulate the paste writing dictated text and recording the expected count.
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("dictated", forType: .string))
        let expectedChangeCount = pasteboard.changeCount

        // No external modification occurs; the guard condition holds.
        XCTAssertEqual(pasteboard.changeCount, expectedChangeCount)
        if pasteboard.changeCount == expectedChangeCount {
            TextInserter.restorePasteboard(snapshot, to: pasteboard)
        }

        XCTAssertEqual(pasteboard.string(forType: .string), "user original")
    }

    /// An external write between snapshot and restore bumps changeCount past the
    /// expected value, so the production guard skips restore and the external
    /// content is left intact rather than being clobbered by the stale snapshot.
    func testChangedChangeCountSkipsRestore() {
        let pasteboard = makeIsolatedPasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("user original", forType: .string))
        let snapshot = TextInserter.snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("dictated", forType: .string))
        let expectedChangeCount = pasteboard.changeCount

        // Another app writes the clipboard before restore fires.
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("external app content", forType: .string))
        XCTAssertNotEqual(pasteboard.changeCount, expectedChangeCount)

        // Mirror the production guard: skip restore when the count moved.
        if pasteboard.changeCount == expectedChangeCount {
            TextInserter.restorePasteboard(snapshot, to: pasteboard)
        }

        // The external content survives; the stale snapshot did not overwrite it.
        XCTAssertEqual(pasteboard.string(forType: .string), "external app content")
    }
}
