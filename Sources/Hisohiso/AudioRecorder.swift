import AVFoundation
import Foundation

/// Error types for audio recording
enum AudioRecorderError: Error, LocalizedError {
    case engineStartFailed(Error)
    case noInputNode
    case permissionDenied
    case notRecording

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            return "No audio input node available"
        case .permissionDenied:
            return "Microphone permission denied"
        case .notRecording:
            return "Not currently recording"
        }
    }
}

/// Records audio from the system default input device using AVAudioEngine
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var isRecording = false

    /// Target sample rate for WhisperKit (16kHz)
    private let targetSampleRate: Double = 16000

    /// Called periodically with audio samples for streaming transcription
    var onAudioChunk: (([Float]) -> Void)?

    /// Check and request microphone permission
    /// - Returns: true if permission granted
    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Start recording audio
    /// - Throws: AudioRecorderError if recording fails to start
    func startRecording() throws {
        guard !isRecording else {
            logWarning("Already recording")
            return
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.noInputNode
        }

        logInfo("Starting recording at \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Clear previous buffer
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputSampleRate: inputFormat.sampleRate)
        }

        do {
            try engine.start()
            isRecording = true
            logInfo("Recording started")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Stop recording and return the captured audio samples
    /// - Returns: Audio samples resampled to 16kHz mono
    func stopRecording() -> [Float] {
        guard isRecording else {
            logWarning("Not recording")
            return []
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        logInfo("Recording stopped, captured \(samples.count) samples (\(Double(samples.count) / targetSampleRate) seconds)")
        return samples
    }

    /// Cancel recording without returning data
    func cancelRecording() {
        guard isRecording else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        logInfo("Recording cancelled")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputSampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Convert to mono if stereo
        var monoSamples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            // Average channels for mono
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        // Resample to 16kHz if needed
        let resampledSamples: [Float]
        if abs(inputSampleRate - targetSampleRate) > 1 {
            resampledSamples = resample(monoSamples, from: inputSampleRate, to: targetSampleRate)
        } else {
            resampledSamples = monoSamples
        }

        bufferLock.lock()
        audioBuffer.append(contentsOf: resampledSamples)
        bufferLock.unlock()

        // Notify for streaming
        onAudioChunk?(resampledSamples)
    }

    /// Simple linear resampling
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = sourceSampleRate / targetSampleRate
        let outputLength = Int(Double(samples.count) / ratio)

        var output = [Float](repeating: 0, count: outputLength)
        for i in 0..<outputLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }
        return output
    }
}
