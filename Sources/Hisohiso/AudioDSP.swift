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

    // MARK: - Noise Handling

    /// Apply a second-order Butterworth high-pass filter.
    /// Removes sub-bass rumble and DC offset that confuse speech models.
    /// At 30Hz cutoff, this is imperceptible to humans but measurably improves WER.
    /// - Parameters:
    ///   - samples: Input audio samples.
    ///   - sampleRate: Sample rate in Hz (default 16000).
    ///   - cutoffHz: Filter cutoff frequency (default 30Hz).
    /// - Returns: High-pass filtered samples.
    static func highPassFilter(
        _ samples: [Float],
        sampleRate: Double = 16000,
        cutoffHz: Float = 30
    ) -> [Float] {
        guard samples.count > 2 else { return samples }

        // Butterworth high-pass biquad coefficients
        let w0 = 2.0 * Float.pi * cutoffHz / Float(sampleRate)
        let cosW0 = cos(w0)
        let alpha = sin(w0) / (2.0 * Float(2.0.squareRoot())) // Q = 1/√2

        let a0 = 1.0 + alpha
        let b0 = ((1.0 + cosW0) / 2.0) / a0
        let b1 = (-(1.0 + cosW0)) / a0
        let b2 = ((1.0 + cosW0) / 2.0) / a0
        let a1 = (-2.0 * cosW0) / a0
        let a2 = (1.0 - alpha) / a0

        var output = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        for i in 0..<samples.count {
            let x = samples[i]
            output[i] = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = output[i]
        }

        return output
    }

    /// Trim leading and trailing silence using energy-based voice activity detection.
    /// Prevents Whisper/Parakeet hallucinations on non-speech segments (e.g., "Thank you
    /// for listening" phantom text). Uses an adaptive threshold based on the recording's
    /// own noise floor.
    /// - Parameters:
    ///   - samples: Input audio samples at target sample rate.
    ///   - sampleRate: Sample rate in Hz (default 16000).
    /// - Returns: Trimmed audio containing speech with 300ms padding, or original if no speech detected.
    static func trimSilence(
        _ samples: [Float],
        sampleRate: Double = 16000
    ) -> [Float] {
        // Don't process very short audio (<0.5s)
        guard samples.count > Int(sampleRate * 0.5) else { return samples }

        let windowSize = Int(sampleRate * 0.03) // 30ms windows
        let windowCount = samples.count / windowSize
        guard windowCount > 0 else { return samples }

        // Calculate RMS energy per window
        var energies = [Float](repeating: 0, count: windowCount)
        for i in 0..<windowCount {
            let offset = i * windowSize
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + offset, 1, &energies[i], vDSP_Length(windowSize))
            }
        }

        // Adaptive threshold: 15th percentile as noise floor, speech = 3× above
        let sorted = energies.sorted()
        let percentileIndex = min(Int(Float(sorted.count) * 0.15), sorted.count - 1)
        let noiseFloor = sorted[percentileIndex]
        let threshold = max(noiseFloor * 3.0, 0.005)

        // Find first and last speech windows
        guard let firstSpeech = energies.firstIndex(where: { $0 > threshold }),
              let lastSpeech = energies.lastIndex(where: { $0 > threshold })
        else {
            logDebug("VAD: No speech detected, passing through")
            return samples
        }

        // Asymmetric padding: 300ms leading (anti-hallucination), 600ms trailing
        // (speech trails off with lower energy that the threshold misses)
        let leadPadWindows = Int(0.3 * sampleRate / Double(windowSize))
        let trailPadWindows = Int(0.6 * sampleRate / Double(windowSize))
        let startWindow = max(0, firstSpeech - leadPadWindows)
        let endWindow = min(windowCount - 1, lastSpeech + trailPadWindows)

        let startSample = startWindow * windowSize
        let endSample = min(samples.count, (endWindow + 1) * windowSize)

        let result = Array(samples[startSample..<endSample])
        let removed = samples.count - result.count

        if removed > Int(sampleRate * 0.1) { // Only log if >100ms removed
            logInfo("VAD: Trimmed \(String(format: "%.1f", Double(removed) / sampleRate))s of silence")
        }

        return result
    }

    // MARK: - Normalization

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
