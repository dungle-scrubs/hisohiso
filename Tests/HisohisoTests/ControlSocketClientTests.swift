@testable import Hisohiso
import Darwin
import Foundation
import XCTest

final class ControlSocketClientTests: XCTestCase {
    func testSendReturnsConnectFailedWhenSocketMissing() {
        let path = "/tmp/hiso-missing-\(UUID().uuidString.prefix(8)).sock"
        let request = ControlRequest.make(method: .ping)

        let result = ControlSocketClient.send(request: request, socketPath: path)
        switch result {
        case .success:
            XCTFail("Expected connect failure")
        case let .failure(error):
            guard case .connectFailed = error else {
                XCTFail("Expected connectFailed, got \(error)")
                return
            }
        }
    }

    func testSendReturnsPathTooLong() {
        let longPath = "/tmp/" + String(repeating: "x", count: 400)
        let request = ControlRequest.make(method: .ping)

        let result = ControlSocketClient.send(request: request, socketPath: longPath)
        switch result {
        case .success:
            XCTFail("Expected path-too-long failure")
        case let .failure(error):
            guard case .pathTooLong = error else {
                XCTFail("Expected pathTooLong, got \(error)")
                return
            }
        }
    }

    func testSendReturnsDecodeFailedForInvalidJSONResponse() throws {
        let path = Self.makeSocketPath()
        let server = try Self.startOneShotServer(path: path, responseLine: "not-json")
        defer {
            _ = server.done.wait(timeout: .now() + 1)
            try? FileManager.default.removeItem(atPath: path)
        }

        let result = ControlSocketClient.send(request: ControlRequest.make(method: .status), socketPath: path)
        switch result {
        case .success:
            XCTFail("Expected decode failure")
        case let .failure(error):
            guard case .decodeFailed = error else {
                XCTFail("Expected decodeFailed, got \(error)")
                return
            }
        }
    }

    func testSendParsesValidResponse() throws {
        let path = Self.makeSocketPath()
        let response = "{\"id\":\"req-1\",\"ok\":true,\"result\":{\"state\":\"idle\",\"model\":\"parakeet-tdt-0.6b-v2\"}}"
        let server = try Self.startOneShotServer(path: path, responseLine: response)
        defer {
            _ = server.done.wait(timeout: .now() + 1)
            try? FileManager.default.removeItem(atPath: path)
        }

        let result = ControlSocketClient.send(request: ControlRequest.make(method: .status), socketPath: path)
        switch result {
        case let .success(decoded):
            XCTAssertTrue(decoded.ok)
            XCTAssertEqual(decoded.result?.state, .idle)
            XCTAssertEqual(decoded.result?.model, "parakeet-tdt-0.6b-v2")
        case let .failure(error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSendReturnsTimedOutWhenServerDoesNotRespondInTime() throws {
        let path = Self.makeSocketPath()
        let response = "{\"id\":\"req-1\",\"ok\":true,\"result\":{\"state\":\"idle\"}}"
        let server = try Self.startOneShotServer(path: path, responseLine: response, responseDelay: 0.2)
        defer {
            _ = server.done.wait(timeout: .now() + 1)
            try? FileManager.default.removeItem(atPath: path)
        }

        let result = ControlSocketClient.send(
            request: ControlRequest.make(method: .status),
            socketPath: path,
            timeout: 0.05
        )

        switch result {
        case .success:
            XCTFail("Expected timeout failure")
        case let .failure(error):
            guard case .timedOut = error else {
                XCTFail("Expected timedOut, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private struct OneShotHandle {
        let done: DispatchSemaphore
    }

    private static func makeSocketPath() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "/tmp/hiso-client-\(suffix).sock"
    }

    private static func startOneShotServer(
        path: String,
        responseLine: String,
        responseDelay: TimeInterval = 0
    ) throws -> OneShotHandle {
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            defer {
                done.signal()
            }

            let listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard listenFD >= 0 else {
                ready.signal()
                return
            }
            defer {
                Darwin.close(listenFD)
                try? FileManager.default.removeItem(atPath: path)
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = path.utf8CString
            let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
            guard bytes.count <= maxLength else {
                ready.signal()
                return
            }

            bytes.withUnsafeBufferPointer { src in
                withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                    dst.update(from: src.baseAddress!, count: src.count)
                }
            }

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.bind(listenFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                ready.signal()
                return
            }

            guard Darwin.listen(listenFD, 1) == 0 else {
                ready.signal()
                return
            }

            ready.signal()

            let clientFD = Darwin.accept(listenFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { Darwin.close(clientFD) }

            var disableSigPipe: Int32 = 1
            _ = setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &disableSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )

            // Drain request bytes until newline.
            var requestData = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(clientFD, &chunk, chunk.count)
                if count <= 0 { break }
                requestData.append(chunk, count: count)
                if requestData.firstIndex(of: 0x0A) != nil { break }
            }

            if responseDelay > 0 {
                usleep(useconds_t(responseDelay * 1_000_000))
            }

            var outbound = Data(responseLine.utf8)
            outbound.append(0x0A)
            _ = outbound.withUnsafeBytes { buffer in
                Darwin.write(clientFD, buffer.baseAddress, buffer.count)
            }
        }

        guard ready.wait(timeout: .now() + 1) == .success else {
            throw NSError(domain: "ControlSocketClientTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server start timed out"])
        }

        return OneShotHandle(done: done)
    }
}
