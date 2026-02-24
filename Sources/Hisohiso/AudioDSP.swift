import Accelerate
import Foundation

/// Shared DSP utilities for audio processing.
/// Used by both `AudioRecorder` and `AudioKitRecorder` to avoid duplicated logic.
enum AudioDSP {
    /// High-quality resampling using vDSP polynomial interpolation.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - sourceSampleRate: Source sample rate (e.g., 48000).
    ///   - targetSampleRate: Target sample rate (e.g., 16000).
    /// - Returns: Resampled audio samples.
    static func resample(
        _ samples: [Float],
        from sourceSampleRate: Double,
        to targetSampleRate: Double
    ) -> [Float] {
        let ratio = Float(sourceSampleRate / targetSampleRate)
        let outputLength = Int(Float(samples.count) / ratio)

        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)
        var control = (0 ..< outputLength).map { Float($0) * ratio }
        vDSP_vlint(samples, &control, 1, &output, 1, vDSP_Length(outputLength), vDSP_Length(samples.count))

        return output
    }

    /// Normalize audio to optimal level for transcription.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - targetPeak: Desired peak amplitude (default 0.9 to leave headroom).
    ///   - maxGain: Maximum gain multiplier to prevent over-amplification (default 20x).
    /// - Returns: Normalized audio samples.
    static func normalize(
        _ samples: [Float],
        targetPeak: Float = 0.9,
        maxGain: Float = 20.0
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }

        // Find peak amplitude
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        // Avoid division by zero and don't amplify near-silence
        guard peak > 0.001 else {
            logDebug("Audio peak too low (\(peak)), returning as-is")
            return samples
        }

        let gain = min(targetPeak / peak, maxGain)
        logDebug("Normalizing audio: peak=\(peak), gain=\(gain)x")

        var output = [Float](repeating: 0, count: samples.count)
        var gainVar = gain
        vDSP_vsmul(samples, 1, &gainVar, &output, 1, vDSP_Length(samples.count))

        return output
    }
}
