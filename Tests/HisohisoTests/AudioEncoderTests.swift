import XCTest
@testable import Hisohiso

final class AudioEncoderTests: XCTestCase {
    // MARK: - WAV Header Validation

    func testEncodeToWAVProducesValidHeader() throws {
        let samples: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0]
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // WAV header is 44 bytes
        XCTAssertGreaterThanOrEqual(data.count, 44)

        // Check RIFF header
        let riff = String(data: data[0 ..< 4], encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")

        // Check WAVE format
        let wave = String(data: data[8 ..< 12], encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")

        // Check fmt subchunk
        let fmt = String(data: data[12 ..< 16], encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")

        // Check data subchunk marker
        let dataMarker = String(data: data[36 ..< 40], encoding: .ascii)
        XCTAssertEqual(dataMarker, "data")
    }

    func testEncodeToWAVCorrectSize() throws {
        let sampleCount = 100
        let samples = [Float](repeating: 0.0, count: sampleCount)
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // Total size = 44 byte header + (sampleCount * 2 bytes per 16-bit sample)
        let expectedSize = 44 + sampleCount * 2
        XCTAssertEqual(data.count, expectedSize)
    }

    func testEncodeToWAVChannelCount() throws {
        let samples: [Float] = [0.0]
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // Offset 22-23: number of channels (UInt16 little-endian)
        let channels = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 22, as: UInt16.self)
        }
        XCTAssertEqual(channels, 1, "Should be mono")
    }

    func testEncodeToWAVSampleRate() throws {
        let samples: [Float] = [0.0]
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // Offset 24-27: sample rate (UInt32 little-endian)
        let sampleRate = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 24, as: UInt32.self)
        }
        XCTAssertEqual(sampleRate, 16000)
    }

    func testEncodeToWAVBitsPerSample() throws {
        let samples: [Float] = [0.0]
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // Offset 34-35: bits per sample (UInt16 little-endian)
        let bitsPerSample = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 34, as: UInt16.self)
        }
        XCTAssertEqual(bitsPerSample, 16)
    }

    // MARK: - Sample Encoding

    func testEncodeToWAVClampsValues() throws {
        // Values outside [-1, 1] should be clamped
        let samples: [Float] = [2.0, -2.0, 0.5]
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        // Read back the PCM samples (offset 44+)
        let pcmData = data.subdata(in: 44 ..< data.count)
        let pcmSamples = pcmData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(pcmSamples.count, 3)
        XCTAssertEqual(pcmSamples[0], Int16.max, "Should clamp to max")
        XCTAssertEqual(pcmSamples[1], -Int16.max, "Should clamp to -max")
    }

    func testEncodeToWAVSilence() throws {
        let samples = [Float](repeating: 0.0, count: 10)
        let data = try XCTUnwrap(AudioEncoder.encodeToWAV(samples: samples, sampleRate: 16000))

        let pcmData = data.subdata(in: 44 ..< data.count)
        let pcmSamples = pcmData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Int16.self))
        }

        for sample in pcmSamples {
            XCTAssertEqual(sample, 0, "Silence should encode to zero")
        }
    }

    func testEncodeToWAVEmptyInput() {
        let data = AudioEncoder.encodeToWAV(samples: [], sampleRate: 16000)
        XCTAssertNotNil(data)
        // Header only, no audio data
        XCTAssertEqual(data?.count, 44)
    }
}
