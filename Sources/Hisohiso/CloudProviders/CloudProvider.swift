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
            return "Cloud provider not configured"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API error: \(message)"
        case .audioEncodingFailed:
            return "Failed to encode audio"
        }
    }
}

/// Available cloud providers
enum CloudProviderType: String, CaseIterable {
    case openAI = "openai"
    case groq = "groq"

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI Whisper"
        case .groq: return "Groq Whisper"
        }
    }

    var keychainType: KeychainManager.APIKeyType {
        switch self {
        case .openAI: return .openAI
        case .groq: return .groq
        }
    }
}
