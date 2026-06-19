@testable import Hisohiso
import Darwin
import Foundation
import XCTest

final class ControlServerTests: XCTestCase {
    private var server: ControlServer?
    private var socketPath: String = ""

    override func tearDown() {
        server?.stop()
        server = nil
        if !socketPath.isEmpty {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        super.tearDown()
    }

    func testControlServerHandlesValidRequest() throws {
        socketPath = Self.makeSocketPath()
        let expectedModel = "parakeet-tdt-0.6b-v2"

        server = ControlServer(socketPath: socketPath) { request, reply in
            XCTAssertEqual(request.method, .ping)
            reply(
                ControlResponse.success(
                    id: request.id,
                    result: ControlResult(state: .idle, message: nil, text: nil, model: expectedModel)
                )
            )
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let request = ControlRequest.make(method: .ping)
        let result = ControlSocketClient.send(request: request, socketPath: socketPath)

        switch result {
        case let .success(response):
            guard response.ok else {
                XCTFail("Expected success response, got error: \(response.error ?? "unknown")")
                return
            }

            XCTAssertEqual(response.id, request.id)
            XCTAssertEqual(response.result?.state, .idle)
            XCTAssertEqual(response.result?.model, expectedModel)
        case let .failure(error):
            XCTFail("Unexpected socket client failure: \(error)")
        }
    }

    func testControlServerRemovesStaleSocketPathBeforeBind() throws {
        socketPath = Self.makeSocketPath()
        _ = FileManager.default.createFile(atPath: socketPath, contents: Data("stale".utf8))

        server = ControlServer(socketPath: socketPath) { request, reply in
            reply(ControlResponse.success(id: request.id, result: ControlResult(state: .idle, message: nil, text: nil, model: nil)))
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let result = ControlSocketClient.send(request: ControlRequest.make(method: .ping), socketPath: socketPath)
        switch result {
        case let .success(response):
            XCTAssertTrue(response.ok)
        case let .failure(error):
            XCTFail("Expected server to recover from stale socket path, got \(error)")
        }
    }

    func testControlServerReturnsFailureForInvalidJSONRequest() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { _, _ in
            XCTFail("Handler should not run for invalid JSON")
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let responseData = try Self.sendRaw(path: socketPath, payload: "{invalid-json}\n")
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Invalid control request")
        XCTAssertNotNil(response.id)
    }

    func testControlServerReturnsFailureForOversizedInvalidRequest() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { _, _ in
            XCTFail("Handler should not run for oversized invalid payload")
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let oversized = String(repeating: "x", count: 70_000) + "\n"
        let responseData = try Self.sendRaw(path: socketPath, payload: oversized)
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Control request too large")
    }

    func testControlServerHandlesPartialRequestFrames() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { request, reply in
            reply(ControlResponse.success(id: request.id, result: ControlResult(state: .idle, message: nil, text: nil, model: nil)))
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let request = ControlRequest(id: "partial-1", method: .ping, params: nil)
        let payload = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? "{}"
        let responseData = try Self.sendRawChunks(path: socketPath, chunks: [String(payload.prefix(8)), String(payload.dropFirst(8)) + "\n"])
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "partial-1")
    }

    func testControlServerHandlesMultipleRequestFramesPerConnection() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { request, reply in
            reply(ControlResponse.success(id: request.id, result: ControlResult(state: .idle, message: nil, text: nil, model: nil)))
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let first = ControlRequest(id: "frame-1", method: .ping, params: nil)
        let second = ControlRequest(id: "frame-2", method: .status, params: nil)
        let payload = try [first, second]
            .map { String(data: try JSONEncoder().encode($0), encoding: .utf8) ?? "{}" }
            .joined(separator: "\n") + "\n"

        let responses = try Self.sendRawAndReadResponses(path: socketPath, payload: payload, expectedResponses: 2)

        XCTAssertEqual(responses.map(\.id), ["frame-1", "frame-2"])
        XCTAssertTrue(responses.allSatisfy(\.ok))
    }

    func testControlServerRejectsOversizedValidJSONWithRequestID() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { _, _ in
            XCTFail("Handler should not run for oversized valid payload")
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let oversizedParams = String(repeating: "x", count: 70_000)
        let payload = "{\"id\":\"oversized-1\",\"method\":\"start\",\"params\":{\"model\":\"\(oversizedParams)\"}}\n"
        let responseData = try Self.sendRaw(path: socketPath, payload: payload)
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "oversized-1")
        XCTAssertEqual(response.error, "Control request too large")
    }

    func testControlServerPreservesRequestIDForKnownMalformedRequest() throws {
        socketPath = Self.makeSocketPath()
        server = ControlServer(socketPath: socketPath) { _, _ in
            XCTFail("Handler should not run for malformed payload")
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let responseData = try Self.sendRaw(path: socketPath, payload: "{\"id\":\"bad-method\",\"method\":\"unknown\"}\n")
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "bad-method")
        XCTAssertEqual(response.error, "Invalid control request")
    }

    func testControlServerStopDuringRequestHandlingDoesNotHangClient() throws {
        socketPath = Self.makeSocketPath()
        let handlerStarted = DispatchSemaphore(value: 0)
        let allowReply = DispatchSemaphore(value: 0)

        server = ControlServer(socketPath: socketPath) { request, reply in
            handlerStarted.signal()
            DispatchQueue.global(qos: .utility).async {
                _ = allowReply.wait(timeout: .now() + 1)
                reply(ControlResponse.failure(id: request.id, error: "Hisohiso app is shutting down"))
            }
        }

        try server?.start()
        try Self.waitForSocket(path: socketPath)

        let request = ControlRequest(id: "shutdown-1", method: .stop, params: nil)
        let path = socketPath
        var result: Result<Data, Error>?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            result = Result {
                let data = try JSONEncoder().encode(request)
                let payload = try XCTUnwrap(String(data: data, encoding: .utf8)) + "\n"
                return try Self.sendRaw(path: path, payload: payload)
            }
            done.signal()
        }

        XCTAssertEqual(handlerStarted.wait(timeout: .now() + 1), .success)
        server?.stop()
        allowReply.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 1), .success)

        let responseData = try XCTUnwrap(result?.get())
        let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.id, "shutdown-1")
        XCTAssertEqual(response.error, "Hisohiso app is shutting down")
    }

    // MARK: - Helpers

    /// Build a short unique socket path under /tmp.
    private static func makeSocketPath() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "/tmp/hiso-control-\(suffix).sock"
    }

    /// Wait until the socket path exists.
    private static func waitForSocket(path: String, timeoutSeconds: TimeInterval = 1.0) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            usleep(10_000)
        }
        throw NSError(domain: "ControlServerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket not ready: \(path)"])
    }

    /// Send raw bytes to a Unix socket and return one newline-delimited response.
    private static func sendRaw(path: String, payload: String) throws -> Data {
        try sendRawChunks(path: path, chunks: [payload])
    }

    /// Send raw chunks to a Unix socket and return one newline-delimited response.
    private static func sendRawChunks(path: String, chunks: [String]) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "ControlServerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let bytes = path.utf8CString
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= maxLength else {
            throw NSError(domain: "ControlServerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Path too long"])
        }

        bytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw NSError(
                domain: "ControlServerTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to connect: \(String(cString: strerror(errno)))"]
            )
        }

        for chunk in chunks {
            let payloadData = Data(chunk.utf8)
            _ = payloadData.withUnsafeBytes { buffer in
                Darwin.write(fd, buffer.baseAddress, buffer.count)
            }
            usleep(10_000)
        }

        return try readResponseData(from: fd)
    }

    /// Send raw bytes and decode multiple newline-delimited responses.
    private static func sendRawAndReadResponses(path: String, payload: String, expectedResponses: Int) throws -> [ControlResponse] {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "ControlServerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        defer { Darwin.close(fd) }

        try connect(fd: fd, path: path)

        let payloadData = Data(payload.utf8)
        _ = payloadData.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        Darwin.shutdown(fd, SHUT_WR)

        var responseData = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            responseData.append(chunk, count: count)
        }

        let lines = responseData.split(separator: 0x0A).prefix(expectedResponses)
        return try lines.map { try JSONDecoder().decode(ControlResponse.self, from: Data($0)) }
    }

    /// Connect a Unix socket file descriptor to a path.
    private static func connect(fd: Int32, path: String) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let bytes = path.utf8CString
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= maxLength else {
            throw NSError(domain: "ControlServerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Path too long"])
        }

        bytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw NSError(
                domain: "ControlServerTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to connect: \(String(cString: strerror(errno)))"]
            )
        }
    }

    /// Read one newline-delimited response from a connected socket.
    private static func readResponseData(from fd: Int32) throws -> Data {
        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 {
                break
            }
            response.append(chunk, count: count)
            if let newlineIndex = response.firstIndex(of: 0x0A) {
                return response.prefix(upTo: newlineIndex)
            }
        }

        throw NSError(domain: "ControlServerTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "No response from server"])
    }
}
