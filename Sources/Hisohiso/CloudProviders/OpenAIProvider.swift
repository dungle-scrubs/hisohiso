import Foundation

/// OpenAI Whisper API provider
final class OpenAIProvider: BaseCloudProvider {
    init() {
        super.init(
            id: "openai",
            displayName: "OpenAI Whisper",
            apiURL: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            model: "whisper-1",
            keychainKeyType: .openAI
        )
    }
}
