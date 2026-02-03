import Foundation

/// Utility for encoding audio samples to various formats
enum AudioEncoder {
    /// Encode Float samples to WAV format
    /// - Parameters:
    ///   - samples: Audio samples (normalized -1.0 to 1.0)
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: WAV file data, or nil if encoding fails
    static func encodeToWAV(samples: [Float], sampleRate: Int) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16)) // Subchunk1Size (16 for PCM)
        data.append(littleEndian: UInt16(1)) // AudioFormat (1 = PCM)
        data.append(littleEndian: numChannels)
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)

        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)

        // Convert Float samples to 16-bit PCM
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))
            data.append(littleEndian: intSample)
        }

        return data
    }
}

// MARK: - Data Extensions

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { buffer in
            append(contentsOf: buffer)
        }
    }
}
