import Foundation

/// Protocol for cloud transcription providers
protocol CloudProvider: Sendable {
    /// Provider identifier
    var id: String { get }

    /// Human-readable name
    var displayName: String { get }

    /// Check if the provider is configured (has API key)
    var isConfigured: Bool { get }

    /// Transcribe audio samples using the cloud API
    /// - Parameter audioSamples: Audio samples at 16kHz mono
    /// - Returns: Transcribed text
    func transcribe(_ audioSamples: [Float]) async throws -> String
}

/// Errors that can occur during cloud transcription
enum CloudTranscriptionError: Error, LocalizedError {
    case notConfigured
    case invalidAPIKey
    case rateLimited
    case networkError(Error)
    case invalidResponse
    case apiError(statusCode: Int, provider: String, code: String)
    case audioEncodingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Cloud provider not configured"
        case .invalidAPIKey:
            "Invalid API key"
        case .rateLimited:
            "Rate limited - please try again later"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            "Invalid response from server"
        case let .apiError(statusCode, provider, code):
            "\(provider) API error (HTTP \(statusCode), code: \(code))"
        case .audioEncodingFailed:
            "Failed to encode audio"
        }
    }

    /// Build a sanitized API error from an upstream response body.
    /// - Parameters:
    ///   - statusCode: HTTP status code returned by the provider.
    ///   - provider: Human-readable provider name for diagnostics.
    ///   - responseBody: Raw response body; parsed only for stable error codes.
    /// - Returns: A sanitized API error that never exposes the raw response body.
    static func sanitizedAPIError(statusCode: Int, provider: String, responseBody: Data) -> CloudTranscriptionError {
        .apiError(
            statusCode: statusCode,
            provider: provider,
            code: CloudAPIErrorSanitizer.code(from: responseBody, statusCode: statusCode)
        )
    }
}

/// Sanitizes cloud provider error payloads into stable, non-secret codes.
enum CloudAPIErrorSanitizer {
    /// Extract a stable error code from provider JSON without exposing messages.
    /// - Parameters:
    ///   - responseBody: Raw provider response body.
    ///   - statusCode: HTTP status code used when no safe code exists.
    /// - Returns: A sanitized error code safe for logs and user-visible errors.
    static func code(from responseBody: Data, statusCode: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: responseBody) else {
            return "http_\(statusCode)"
        }

        if let dictionary = object as? [String: Any] {
            if let code = codeValue(in: dictionary) {
                return sanitize(code, fallbackStatusCode: statusCode)
            }

            if let error = dictionary["error"] as? [String: Any], let code = codeValue(in: error) {
                return sanitize(code, fallbackStatusCode: statusCode)
            }
        }

        return "http_\(statusCode)"
    }

    /// Find a likely provider error-code field in a JSON dictionary.
    /// - Parameter dictionary: JSON dictionary to inspect.
    /// - Returns: The provider-supplied code or type when present.
    private static func codeValue(in dictionary: [String: Any]) -> String? {
        (dictionary["code"] as? String) ?? (dictionary["type"] as? String)
    }

    /// Strip unsafe characters and bound the diagnostic code length.
    /// - Parameters:
    ///   - value: Provider-supplied code value.
    ///   - fallbackStatusCode: HTTP status code used if the value is empty.
    /// - Returns: Sanitized lowercase code safe for logs and UI.
    private static func sanitize(_ value: String, fallbackStatusCode: Int) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let sanitized = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
            .prefix(64)

        return sanitized.isEmpty ? "http_\(fallbackStatusCode)" : String(sanitized)
    }
}

/// Available cloud providers
enum CloudProviderType: String, CaseIterable {
    case openAI = "openai"
    case groq

    var displayName: String {
        switch self {
        case .openAI: "OpenAI Whisper"
        case .groq: "Groq Whisper"
        }
    }

    var keychainType: KeychainManager.APIKeyType {
        switch self {
        case .openAI: .openAI
        case .groq: .groq
        }
    }
}

/// Shared implementation for OpenAI-compatible transcription APIs.
///
/// Both OpenAI and Groq use identical request/response formats.
/// Subclasses only need to provide URL, model name, and API key.
class BaseCloudProvider: CloudProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let apiURL: URL
    let model: String
    let keychainKeyType: KeychainManager.APIKeyType

    /// URL session used for transcription requests.
    /// Injectable so tests can drive the 200/401/429/error dispatch without live network.
    let urlSession: URLSession

    /// Request timeout in seconds
    private let timeoutInterval: TimeInterval = 30

    init(
        id: String,
        displayName: String,
        apiURL: URL,
        model: String,
        keychainKeyType: KeychainManager.APIKeyType,
        urlSession: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.apiURL = apiURL
        self.model = model
        self.keychainKeyType = keychainKeyType
        self.urlSession = urlSession
    }

    var isConfigured: Bool {
        KeychainManager.shared.hasAPIKey(keychainKeyType)
    }

    func transcribe(_ audioSamples: [Float]) async throws -> String {
        guard let apiKey = KeychainManager.shared.getAPIKey(keychainKeyType) else {
            throw CloudTranscriptionError.notConfigured
        }

        guard let wavData = AudioEncoder.encodeToWAV(samples: audioSamples, sampleRate: 16000) else {
            throw CloudTranscriptionError.audioEncodingFailed
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField("model", value: model, boundary: boundary)
        body.appendFormFile("file", filename: "audio.wav", contentType: "audio/wav", data: wavData, boundary: boundary)
        body.appendFormField("response_format", value: "json", boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        logInfo("\(displayName): sending \(wavData.count) bytes of audio")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudTranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String
                else {
                    throw CloudTranscriptionError.invalidResponse
                }
                logInfo("\(displayName): transcription complete")
                return text
            case 401:
                throw CloudTranscriptionError.invalidAPIKey
            case 429:
                throw CloudTranscriptionError.rateLimited
            default:
                let error = CloudTranscriptionError.sanitizedAPIError(
                    statusCode: httpResponse.statusCode,
                    provider: displayName,
                    responseBody: data
                )
                logError("\(displayName): \(error.localizedDescription)")
                throw error
            }
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            throw CloudTranscriptionError.networkError(error)
        }
    }
}

// MARK: - Data Multipart Helpers

private extension Data {
    mutating func appendFormField(_ name: String, value: String, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }

    mutating func appendFormFile(_ name: String, filename: String, contentType: String, data: Data, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        append(data)
        append(Data("\r\n".utf8))
    }
}
