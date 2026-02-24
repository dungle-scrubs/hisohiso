import Foundation

/// Groq Whisper API provider (faster inference)
final class GroqProvider: BaseCloudProvider {
    /// Groq model identifier. Update if Groq renames or deprecates the model.
    static let modelName = "whisper-large-v3"

    init() {
        super.init(
            id: "groq",
            displayName: "Groq Whisper",
            apiURL: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
            model: Self.modelName,
            keychainKeyType: .groq
        )
    }
}
