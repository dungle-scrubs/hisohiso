import Foundation
@testable import Hisohiso
import XCTest

/// Exercises `BaseCloudProvider.transcribe` status-code dispatch by injecting a
/// `URLSession` backed by `StubURLProtocol`, so no live network is required.
final class CloudProviderTests: XCTestCase {
    private let keyType: KeychainManager.APIKeyType = .openAI
    private var savedKey: String?

    override func setUp() {
        super.setUp()
        // Preserve any real developer key so the test never destroys it.
        savedKey = KeychainManager.shared.getAPIKey(keyType)
        KeychainManager.shared.setAPIKey("test-api-key", type: keyType)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        if let savedKey {
            KeychainManager.shared.setAPIKey(savedKey, type: keyType)
        } else {
            KeychainManager.shared.deleteAPIKey(keyType)
        }
        super.tearDown()
    }

    // MARK: - Success

    func testSuccessReturnsTranscribedText() async throws {
        StubURLProtocol.stub(statusCode: 200, body: Data("{\"text\":\"hello world\"}".utf8))
        let provider = try makeProvider()

        let text = try await provider.transcribe(sampleAudio())

        XCTAssertEqual(text, "hello world")
    }

    func testSuccessWithMalformedBodyThrowsInvalidResponse() async throws {
        StubURLProtocol.stub(statusCode: 200, body: Data("not json".utf8))
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case .invalidResponse = error else {
                XCTFail("expected .invalidResponse, got \(error)")
                return
            }
        }
    }

    func testSuccessWithoutTextFieldThrowsInvalidResponse() async throws {
        StubURLProtocol.stub(statusCode: 200, body: Data("{\"other\":\"value\"}".utf8))
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case .invalidResponse = error else {
                XCTFail("expected .invalidResponse, got \(error)")
                return
            }
        }
    }

    // MARK: - Status-code dispatch

    func testUnauthorizedThrowsInvalidAPIKey() async throws {
        StubURLProtocol.stub(statusCode: 401, body: Data())
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case .invalidAPIKey = error else {
                XCTFail("expected .invalidAPIKey, got \(error)")
                return
            }
        }
    }

    func testTooManyRequestsThrowsRateLimited() async throws {
        StubURLProtocol.stub(statusCode: 429, body: Data())
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case .rateLimited = error else {
                XCTFail("expected .rateLimited, got \(error)")
                return
            }
        }
    }

    func testServerErrorThrowsSanitizedAPIError() async throws {
        let body = Data("{\"error\":{\"message\":\"secret sk-live token\",\"code\":\"server_overloaded\"}}".utf8)
        StubURLProtocol.stub(statusCode: 500, body: body)
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case let .apiError(statusCode, provider, code) = error else {
                XCTFail("expected .apiError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(provider, "Test Provider")
            XCTAssertEqual(code, "server_overloaded")
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.contains("secret"))
            XCTAssertFalse(description.contains("sk-live"))
        }
    }

    func testOtherClientErrorThrowsSanitizedAPIError() async throws {
        StubURLProtocol.stub(statusCode: 403, body: Data("forbidden raw detail".utf8))
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case let .apiError(statusCode, _, code) = error else {
                XCTFail("expected .apiError, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
            // No safe JSON code, so the sanitizer falls back to the status code.
            XCTAssertEqual(code, "http_403")
        }
    }

    // MARK: - Transport failure

    func testTransportFailureThrowsNetworkError() async throws {
        StubURLProtocol.stub(error: URLError(.notConnectedToInternet))
        let provider = try makeProvider()

        await assertTranscribeThrows(provider) { error in
            guard case let .networkError(underlying) = error else {
                XCTFail("expected .networkError, got \(error)")
                return
            }
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        }
    }

    // MARK: - Helpers

    private func makeProvider() throws -> BaseCloudProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://transcribe.test/v1/audio/transcriptions"))
        return BaseCloudProvider(
            id: "test",
            displayName: "Test Provider",
            apiURL: url,
            model: "whisper-1",
            keychainKeyType: keyType,
            urlSession: session
        )
    }

    private func sampleAudio() -> [Float] {
        (0 ..< 1600).map { Float(sin(Double($0) * 0.05)) }
    }

    /// Runs `transcribe` expecting a `CloudTranscriptionError`, then hands it to
    /// `assert` for case-specific checks.
    private func assertTranscribeThrows(
        _ provider: BaseCloudProvider,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ assert: (CloudTranscriptionError) -> Void
    ) async {
        do {
            _ = try await provider.transcribe(sampleAudio())
            XCTFail("expected transcribe to throw", file: file, line: line)
        } catch let error as CloudTranscriptionError {
            assert(error)
        } catch {
            XCTFail("expected CloudTranscriptionError, got \(error)", file: file, line: line)
        }
    }
}

// MARK: - Stub URLProtocol

/// A `URLProtocol` that replays a single configured response or transport error.
/// Configuration lives in a lock-guarded store so the strict-concurrency checker
/// is satisfied without sharing mutable static state unsafely.
final class StubURLProtocol: URLProtocol {
    private struct Response {
        let statusCode: Int
        let body: Data
        let error: Error?
    }

    private final class Store: @unchecked Sendable {
        static let shared = Store()
        private let lock = NSLock()
        private var response: Response?

        func set(_ response: Response?) {
            lock.lock()
            defer { lock.unlock() }
            self.response = response
        }

        func get() -> Response? {
            lock.lock()
            defer { lock.unlock() }
            return response
        }
    }

    static func stub(statusCode: Int, body: Data) {
        Store.shared.set(Response(statusCode: statusCode, body: body, error: nil))
    }

    static func stub(error: Error) {
        Store.shared.set(Response(statusCode: 0, body: Data(), error: error))
    }

    static func reset() {
        Store.shared.set(nil)
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = Store.shared.get()

        if let error = response?.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response?.statusCode ?? 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response?.body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
