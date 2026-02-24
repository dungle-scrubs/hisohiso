import Foundation

/// Groq Whisper API provider (faster inference)
final class GroqProvider: BaseCloudProvider {
    init() {
        super.init(
            id: "groq",
            displayName: "Groq Whisper",
            apiURL: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
            model: "whisper-large-v3",
            keychainKeyType: .groq
        )
    }
}
