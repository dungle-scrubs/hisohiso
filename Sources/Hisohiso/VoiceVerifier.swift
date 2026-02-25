import Accelerate
@preconcurrency import CoreML
import Foundation

/// Speaker verification using CoreML embedding model (Resemblyzer).
/// Compares voice embeddings to determine if the speaker matches the enrolled user.
///
/// Uses a dedicated actor to keep heavy DSP (mel spectrogram, FFT) and CoreML inference
/// off the main thread. UI-facing properties (`isEnabled`, `threshold`) are backed by
/// UserDefaults which is thread-safe for atomic reads/writes.
final class VoiceVerifier: @unchecked Sendable {
    /// Shared instance
    static let shared = VoiceVerifier()

    /// Audio sample rate expected by the model
    static let sampleRate: Float = 16000

    /// Minimum samples required for verification (2 seconds at 16kHz)
    static let minSamplesForVerification = AppConstants.minVoiceVerificationSamples

    /// Embedding dimension (Resemblyzer outputs 256-dim)
    static let embeddingDimension = 256

    /// Mel spectrogram parameters (matching Resemblyzer)
    private static let nMels = 40
    private static let hopLength = 160 // 10ms at 16kHz
    private static let winLength = 400 // 25ms at 16kHz
    private static let nFft = 512
    private static let partialFrames = 160 // Required by model

    /// The CoreML model for generating speaker embeddings
    private var model: MLModel?

    /// Enrolled user's voice embedding (average of enrollment samples)
    private var enrolledEmbedding: [Float]?

    /// Mel filterbank matrix (precomputed)
    private var melFilterbank: [[Float]]?

    /// Protects `model` and `enrolledEmbedding` for thread-safe reads.
    private let lock = NSLock()

    /// Verification threshold (0.0 - 1.0, higher = stricter).
    /// Backed by UserDefaults (atomic for simple types).
    var threshold: Float {
        get { Float(UserDefaults.standard.double(for: .voiceVerificationThreshold)) }
        set { UserDefaults.standard.set(Double(newValue), for: .voiceVerificationThreshold) }
    }

    /// Whether verification is enabled.
    /// Backed by UserDefaults (atomic for simple types).
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(for: .voiceVerificationEnabled) }
        set { UserDefaults.standard.set(newValue, for: .voiceVerificationEnabled) }
    }

    /// Whether a voice is enrolled
    var isEnrolled: Bool {
        lock.withLock { enrolledEmbedding != nil }
    }

    private init() {
        // Set default threshold if not set
        if !UserDefaults.standard.hasValue(for: .voiceVerificationThreshold) {
            threshold = AppConstants.defaultVoiceVerificationThreshold
        }

        computeMelFilterbank()
        loadModel()
        loadEnrolledEmbedding()
    }

    // MARK: - Mel Filterbank

    private func computeMelFilterbank() {
        /// Convert Hz to Mel scale
        func hzToMel(_ hz: Float) -> Float {
            2595 * log10(1 + hz / 700)
        }

        func melToHz(_ mel: Float) -> Float {
            700 * (pow(10, mel / 2595) - 1)
        }

        let fMin: Float = 0
        let fMax = Self.sampleRate / 2
        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)

        // Create mel points
        let nMels = Self.nMels
        let nFft = Self.nFft
        var melPoints = [Float](repeating: 0, count: nMels + 2)
        for i in 0..<nMels + 2 {
            let mel = melMin + Float(i) * (melMax - melMin) / Float(nMels + 1)
            melPoints[i] = melToHz(mel)
        }

        // Convert to FFT bin indices
        let binPoints = melPoints.map { Int(floor(($0 / Self.sampleRate) * Float(nFft))) }

        // Create filterbank
        var filterbank = [[Float]](repeating: [Float](repeating: 0, count: nFft / 2 + 1), count: nMels)
        for m in 0..<nMels {
            for k in binPoints[m]..<binPoints[m + 1] where k < nFft / 2 + 1 {
                filterbank[m][k] = Float(k - binPoints[m]) / Float(binPoints[m + 1] - binPoints[m])
            }
            for k in binPoints[m + 1]..<binPoints[m + 2] where k < nFft / 2 + 1 {
                filterbank[m][k] = Float(binPoints[m + 2] - k) / Float(binPoints[m + 2] - binPoints[m + 1])
            }
        }

        melFilterbank = filterbank
    }

    // MARK: - Model Loading

    private func loadModel() {
        // Try to load from bundle first
        if let modelURL = Bundle.main.url(forResource: "SpeakerEmbedding", withExtension: "mlpackage") ??
            Bundle.main.url(forResource: "SpeakerEmbedding", withExtension: "mlmodelc")
        {
            do {
                model = try MLModel(contentsOf: modelURL)
                logInfo("VoiceVerifier: Loaded model from bundle")
                return
            } catch {
                logError("VoiceVerifier: Failed to load model from bundle: \(error)")
            }
        }

        // Try common dev paths
        // Paths relative to the working directory (for dev builds run via `swift run`)
        let devPaths = [
            URL(fileURLWithPath: "Resources/SpeakerEmbedding.mlpackage"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/SpeakerEmbedding.mlpackage"),
        ]

        for path in devPaths {
            logDebug("VoiceVerifier: Trying model path: \(path.path)")
            if FileManager.default.fileExists(atPath: path.path) {
                do {
                    let compiledURL = try MLModel.compileModel(at: path)
                    model = try MLModel(contentsOf: compiledURL)
                    logInfo("VoiceVerifier: Loaded model from \(path.path)")
                    return
                } catch {
                    logError("VoiceVerifier: Failed to compile model at \(path.path): \(error)")
                }
            }
        }

        logWarning("VoiceVerifier: Model not found in any location")
    }

    // MARK: - Mel Spectrogram Computation

    /// Compute mel spectrogram from audio samples
    private func computeMelSpectrogram(from audioSamples: [Float]) -> [[Float]]? {
        guard let filterbank = melFilterbank else { return nil }

        let hopLength = Self.hopLength
        let winLength = Self.winLength
        let nFft = Self.nFft

        // Number of frames
        let nFrames = (audioSamples.count - winLength) / hopLength + 1
        guard nFrames > 0 else { return nil }

        var melSpec = [[Float]]()

        // Hann window
        var window = [Float](repeating: 0, count: winLength)
        vDSP_hann_window(&window, vDSP_Length(winLength), Int32(vDSP_HANN_NORM))

        // FFT setup
        let log2n = vDSP_Length(log2(Float(nFft)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        for frame in 0..<nFrames {
            let start = frame * hopLength

            // Extract and window the frame
            var windowedFrame = [Float](repeating: 0, count: nFft)
            for i in 0..<winLength where start + i < audioSamples.count {
                windowedFrame[i] = audioSamples[start + i] * window[i]
            }

            // Compute FFT
            var realPart = [Float](repeating: 0, count: nFft / 2)
            var imagPart = [Float](repeating: 0, count: nFft / 2)

            realPart.withUnsafeMutableBufferPointer { realBuffer in
                imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                    guard let realBase = realBuffer.baseAddress,
                          let imagBase = imagBuffer.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    // Safety: Float and DSPComplex (two Floats) share 4-byte alignment.
                    // Swift's withMemoryRebound is defined behavior when alignment matches.
                    windowedFrame.withUnsafeBufferPointer { ptr in
                        guard let base = ptr.baseAddress else { return }
                        base.withMemoryRebound(to: DSPComplex.self, capacity: nFft / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(nFft / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Compute power spectrum
            var powerSpectrum = [Float](repeating: 0, count: nFft / 2 + 1)
            for i in 0..<nFft / 2 {
                powerSpectrum[i] = realPart[i] * realPart[i] + imagPart[i] * imagPart[i]
            }

            // Apply mel filterbank
            var melFrame = [Float](repeating: 0, count: Self.nMels)
            for m in 0..<Self.nMels {
                var sum: Float = 0
                for k in 0..<min(powerSpectrum.count, filterbank[m].count) {
                    sum += powerSpectrum[k] * filterbank[m][k]
                }
                // Log mel spectrogram
                melFrame[m] = log(max(sum, 1e-10))
            }

            melSpec.append(melFrame)
        }

        return melSpec
    }

    // MARK: - Embedding Generation

    /// Generate a 256-dimensional speaker embedding from audio samples.
    /// Runs mel spectrogram computation and CoreML inference on a background thread.
    /// - Parameter audioSamples: Audio samples at 16kHz mono (needs ≥2 seconds).
    /// - Returns: 256-dimensional embedding vector.
    /// - Throws: `VoiceVerifierError` if the model is not loaded or audio is insufficient.
    func generateEmbedding(from audioSamples: [Float]) async throws -> [Float] {
        let capturedModel = lock.withLock { model }
        guard let capturedModel else {
            throw VoiceVerifierError.modelNotLoaded
        }

        guard audioSamples.count >= AppConstants.minVoiceVerificationSamples else {
            throw VoiceVerifierError.insufficientAudio(
                required: AppConstants.minVoiceVerificationSamples,
                provided: audioSamples.count
            )
        }

        // Run heavy DSP + CoreML inference on a detached task to avoid blocking
        // the caller's executor. Structured concurrency ensures the task is
        // automatically cancelled if the parent is cancelled.
        return try await Task.detached(priority: .userInitiated) { [self] in
            // Compute mel spectrogram
            guard let melSpec = computeMelSpectrogram(from: audioSamples) else {
                throw VoiceVerifierError.melComputationFailed
            }

            let partialFrames = Self.partialFrames
            guard melSpec.count >= partialFrames else {
                throw VoiceVerifierError.insufficientAudio(
                    required: partialFrames * Self.hopLength,
                    provided: audioSamples.count
                )
            }

            // Take a slice from the middle for better quality
            let startFrame = (melSpec.count - partialFrames) / 2
            let melSlice = Array(melSpec[startFrame..<startFrame + partialFrames])

            // Create MLMultiArray for input: (1, 160, 40)
            let inputArray = try MLMultiArray(
                shape: [1, NSNumber(value: partialFrames), NSNumber(value: Self.nMels)],
                dataType: .float32
            )
            for (frameIdx, frame) in melSlice.enumerated() {
                for (melIdx, value) in frame.enumerated() {
                    let index = frameIdx * Self.nMels + melIdx
                    inputArray[index] = NSNumber(value: value)
                }
            }

            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["mel_spectrogram": inputArray]
            )

            let output = try capturedModel.prediction(from: inputFeatures)

            guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
                throw VoiceVerifierError.invalidOutput
            }

            var embedding = [Float](repeating: 0, count: Self.embeddingDimension)
            for i in 0..<Self.embeddingDimension {
                embedding[i] = embeddingArray[i].floatValue
            }

            return embedding
        }.value
    }

    // MARK: - Enrollment

    /// Enroll a new voice using multiple audio samples.
    /// - Parameter samples: Array of audio sample arrays (each should be ≥2 seconds at 16kHz).
    /// - Returns: The averaged, L2-normalized embedding that was enrolled.
    /// - Throws: `VoiceVerifierError` if no valid embeddings could be generated.
    @discardableResult
    func enroll(with samples: [[Float]]) async throws -> [Float] {
        guard !samples.isEmpty else {
            throw VoiceVerifierError.noSamplesProvided
        }

        logInfo("VoiceVerifier: Enrolling with \(samples.count) samples")

        // Generate embeddings for all samples
        var embeddings: [[Float]] = []
        for (index, sample) in samples.enumerated() {
            do {
                let embedding = try await generateEmbedding(from: sample)
                embeddings.append(embedding)
                logDebug("VoiceVerifier: Generated embedding \(index + 1)/\(samples.count)")
            } catch {
                logWarning("VoiceVerifier: Failed to generate embedding for sample \(index): \(error)")
            }
        }

        guard !embeddings.isEmpty else {
            throw VoiceVerifierError.enrollmentFailed
        }

        // Average all embeddings
        let averaged = averageEmbeddings(embeddings)

        // L2 normalize
        let normalized = l2Normalize(averaged)

        // Store enrolled embedding
        lock.withLock { enrolledEmbedding = normalized }
        saveEnrolledEmbedding()

        logInfo("VoiceVerifier: Enrollment complete with \(embeddings.count) embeddings")
        return normalized
    }

    /// Clear enrolled voice
    func clearEnrollment() {
        lock.withLock { enrolledEmbedding = nil }
        _ = KeychainManager.shared.deleteData(forKey: embeddingKeychainKey)
        try? FileManager.default.removeItem(at: embeddingFileURL)
        logInfo("VoiceVerifier: Enrollment cleared")
    }

    // MARK: - Verification

    /// Verify whether the given audio matches the enrolled voice.
    /// - Parameter audioSamples: Audio samples at 16kHz mono (needs ≥2 seconds).
    /// - Returns: Verification result with match status and similarity score.
    /// - Throws: `VoiceVerifierError` if the model is not loaded or audio is insufficient.
    func verify(audioSamples: [Float]) async throws -> VerificationResult {
        guard isEnabled else {
            return VerificationResult(isMatch: true, similarity: 1.0, reason: .verificationDisabled)
        }

        let enrolled = lock.withLock { enrolledEmbedding }
        guard let enrolled else {
            return VerificationResult(isMatch: true, similarity: 1.0, reason: .notEnrolled)
        }

        let currentEmbedding = try await generateEmbedding(from: audioSamples)
        let normalized = l2Normalize(currentEmbedding)
        let similarity = cosineSimilarity(enrolled, normalized)
        let isMatch = similarity >= threshold

        logInfo(
            "VoiceVerifier: Similarity=\(String(format: "%.3f", similarity)), Threshold=\(threshold), Match=\(isMatch)"
        )

        return VerificationResult(
            isMatch: isMatch,
            similarity: similarity,
            reason: isMatch ? .matched : .notMatched
        )
    }

    // MARK: - Vector Operations

    /// L2 normalize a vector
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        guard norm > 0 else { return vector }

        var result = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        return result
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        // Since both vectors are L2 normalized, dot product = cosine similarity
        return dot
    }

    /// Average multiple embeddings into one
    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }

        var result = [Float](repeating: 0, count: first.count)
        for embedding in embeddings {
            for (i, val) in embedding.enumerated() {
                result[i] += val
            }
        }

        var divisor = Float(embeddings.count)
        vDSP_vsdiv(result, 1, &divisor, &result, 1, vDSP_Length(result.count))
        return result
    }

    // MARK: - Persistence

    /// Keychain key for persisted voice embedding.
    private let embeddingKeychainKey = "voice-embedding-v1"

    /// Legacy file path kept only for one-time migration.
    private var embeddingFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Hisohiso")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("voice_embedding.bin")
    }

    private func saveEnrolledEmbedding() {
        guard let embedding = lock.withLock({ enrolledEmbedding }) else { return }

        let data = embedding.withUnsafeBytes { Data($0) }
        switch KeychainManager.shared.setData(data, forKey: embeddingKeychainKey) {
        case .success:
            logDebug("VoiceVerifier: Saved embedding to Keychain")
            // Cleanup legacy file if present.
            try? FileManager.default.removeItem(at: embeddingFileURL)
        case let .failure(error):
            logError("VoiceVerifier: Failed to save embedding to Keychain: \(error.localizedDescription)")
        }
    }

    private func loadEnrolledEmbedding() {
        // Preferred: Keychain
        if let data = KeychainManager.shared.getData(forKey: embeddingKeychainKey),
           let embedding = decodeEmbedding(from: data)
        {
            lock.withLock { enrolledEmbedding = embedding }
            logInfo("VoiceVerifier: Loaded enrolled embedding from Keychain")
            return
        }

        // Legacy migration path: file -> Keychain
        if let data = try? Data(contentsOf: embeddingFileURL),
           let embedding = decodeEmbedding(from: data)
        {
            lock.withLock { enrolledEmbedding = embedding }
            logInfo("VoiceVerifier: Loaded enrolled embedding from legacy file, migrating to Keychain")
            switch KeychainManager.shared.setData(data, forKey: embeddingKeychainKey) {
            case .success:
                try? FileManager.default.removeItem(at: embeddingFileURL)
            case let .failure(error):
                logWarning("VoiceVerifier: Failed to migrate embedding to Keychain: \(error.localizedDescription)")
            }
            return
        }

        logDebug("VoiceVerifier: No enrolled embedding found")
    }

    private func decodeEmbedding(from data: Data) -> [Float]? {
        let floatSize = MemoryLayout<Float>.size
        guard data.count == Self.embeddingDimension * floatSize else {
            let count = data.count / floatSize
            logWarning("VoiceVerifier: Invalid embedding size: \(count), expected \(Self.embeddingDimension)")
            return nil
        }

        var embedding = [Float](repeating: 0, count: Self.embeddingDimension)
        _ = embedding.withUnsafeMutableBytes { bytes in
            data.copyBytes(to: bytes)
        }
        return embedding
    }
}

// MARK: - Types

/// Result of voice verification
struct VerificationResult {
    let isMatch: Bool
    let similarity: Float
    let reason: VerificationReason

    enum VerificationReason {
        case matched
        case notMatched
        case notEnrolled
        case verificationDisabled
    }
}

/// Errors that can occur during voice verification
enum VoiceVerifierError: Error, LocalizedError {
    case modelNotLoaded
    case insufficientAudio(required: Int, provided: Int)
    case invalidOutput
    case noSamplesProvided
    case enrollmentFailed
    case melComputationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speaker verification model not loaded"
        case let .insufficientAudio(required, provided):
            let reqSec = Double(required) / AppConstants.targetSampleRate
            let provSec = Double(provided) / AppConstants.targetSampleRate
            return String(format: "Need %.1fs of audio, only %.1fs provided", reqSec, provSec)
        case .invalidOutput:
            return "Model produced invalid output"
        case .noSamplesProvided:
            return "No audio samples provided for enrollment"
        case .enrollmentFailed:
            return "Failed to enroll voice"
        case .melComputationFailed:
            return "Failed to compute mel spectrogram"
        }
    }
}
