import Foundation

/// Protocol for cloud transcription providers
protocol CloudProvider {
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
    case apiError(String)
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
        case let .apiError(message):
            "API error: \(message)"
        case .audioEncodingFailed:
            "Failed to encode audio"
        }
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
class BaseCloudProvider: CloudProvider {
    let id: String
    let displayName: String
    let apiURL: URL
    let model: String
    let keychainKeyType: KeychainManager.APIKeyType

    /// Request timeout in seconds
    private let timeoutInterval: TimeInterval = 30

    init(id: String, displayName: String, apiURL: URL, model: String, keychainKeyType: KeychainManager.APIKeyType) {
        self.id = id
        self.displayName = displayName
        self.apiURL = apiURL
        self.model = model
        self.keychainKeyType = keychainKeyType
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
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        logInfo("\(displayName): sending \(wavData.count) bytes of audio")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logError("\(displayName): API error \(httpResponse.statusCode): \(errorMessage)")
                throw CloudTranscriptionError.apiError(errorMessage)
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
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFormFile(_ name: String, filename: String, contentType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
