@testable import Hisohiso
import XCTest

final class CrashArchiveStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: CrashArchiveStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashArchiveStoreTests-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        store = CrashArchiveStore(
            crashesDirectory: tempDir.appendingPathComponent("crashes"),
            breadcrumbPath: tempDir.appendingPathComponent(".crash-breadcrumb"),
            pidFilePath: tempDir.appendingPathComponent(".hisohiso.pid"),
            logsDirectory: tempDir.appendingPathComponent("logs"),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCheckPreviousCrashReturnsNilWhenBreadcrumbIsMissing() {
        XCTAssertNil(store.checkPreviousCrash())
    }

    func testCheckPreviousCrashArchivesNonEmptyBreadcrumb() throws {
        try "SIGNAL: SIGSEGV (11)\n".write(to: store.breadcrumbPath, atomically: true, encoding: .utf8)
        try "12345\n".write(to: store.pidFilePath, atomically: true, encoding: .utf8)

        let archive = try XCTUnwrap(store.checkPreviousCrash())

        let breadcrumb = try String(contentsOf: archive.appendingPathComponent("breadcrumb.txt"), encoding: .utf8)
        let systemInfo = try String(contentsOf: archive.appendingPathComponent("system-info.txt"), encoding: .utf8)

        XCTAssertEqual(breadcrumb, "SIGNAL: SIGSEGV (11)")
        XCTAssertTrue(systemInfo.contains("Previous PID: 12345"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.breadcrumbPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFilePath.path))
    }

    func testCheckPreviousCrashIgnoresEmptyBreadcrumbAndCleansFiles() throws {
        try " \n\t".write(to: store.breadcrumbPath, atomically: true, encoding: .utf8)
        try "12345\n".write(to: store.pidFilePath, atomically: true, encoding: .utf8)

        XCTAssertNil(store.checkPreviousCrash())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.breadcrumbPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFilePath.path))
    }

    func testCheckPreviousCrashIgnoresSIGTERMBreadcrumb() throws {
        try "SIGNAL: SIGTERM (15)\n".write(to: store.breadcrumbPath, atomically: true, encoding: .utf8)

        XCTAssertNil(store.checkPreviousCrash())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.breadcrumbPath.path))
    }

    func testArchiveNamingIsDeterministic() throws {
        let archive = try XCTUnwrap(store.archiveCrash(breadcrumb: "DIRTY_EXIT"))

        XCTAssertEqual(archive.lastPathComponent, "crash-2023-11-14T22-13-20Z")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("breadcrumb.txt").path))
    }

    func testCorruptArchiveDestinationReturnsNil() throws {
        try "not a directory".write(to: store.crashesDirectory, atomically: true, encoding: .utf8)

        XCTAssertNil(store.archiveCrash(breadcrumb: "DIRTY_EXIT"))
    }

    func testMarkCleanShutdownRemovesBreadcrumbAndPidFiles() throws {
        try "DIRTY_EXIT".write(to: store.breadcrumbPath, atomically: true, encoding: .utf8)
        try "12345\n".write(to: store.pidFilePath, atomically: true, encoding: .utf8)

        store.markCleanShutdown()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.breadcrumbPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pidFilePath.path))
    }
}
