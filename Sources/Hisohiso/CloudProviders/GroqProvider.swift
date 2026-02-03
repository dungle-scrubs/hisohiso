import Foundation

/// Groq Whisper API provider (faster inference)
final class GroqProvider: CloudProvider {
    let id = "groq"
    let displayName = "Groq Whisper"

    private let apiURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3"

    var isConfigured: Bool {
        KeychainManager.shared.hasAPIKey(.groq)
    }

    func transcribe(_ audioSamples: [Float]) async throws -> String {
        guard let apiKey = KeychainManager.shared.getAPIKey(.groq) else {
            throw CloudTranscriptionError.notConfigured
        }

        // Convert samples to WAV data
        guard let wavData = AudioEncoder.encodeToWAV(samples: audioSamples, sampleRate: 16000) else {
            throw CloudTranscriptionError.audioEncodingFailed
        }

        // Create multipart form data (same format as OpenAI)
        let boundary = UUID().uuidString
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logInfo("Groq: sending \(wavData.count) bytes of audio")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudTranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                // Parse response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String
                else {
                    throw CloudTranscriptionError.invalidResponse
                }
                logInfo("Groq: transcription complete")
                return text

            case 401:
                throw CloudTranscriptionError.invalidAPIKey

            case 429:
                throw CloudTranscriptionError.rateLimited

            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logError("Groq: API error \(httpResponse.statusCode): \(errorMessage)")
                throw CloudTranscriptionError.apiError(errorMessage)
            }
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            throw CloudTranscriptionError.networkError(error)
        }
    }
}
