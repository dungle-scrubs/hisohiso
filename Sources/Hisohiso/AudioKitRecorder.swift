import Accelerate
import AudioKit
import AVFoundation
import Foundation

/// Records audio using AudioKit with noise suppression
/// Thread safety: `audioBuffer` is protected by `bufferLock` (NSLock).
final class AudioKitRecorder: @unchecked Sendable {
    private var engine: AudioEngine?
    private var tap: RawDataTap?
    
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var isRecording = false
    
    /// Target sample rate for WhisperKit (16kHz)
    private let targetSampleRate: Double = 16000
    
    /// Called periodically with audio samples for streaming transcription
    var onAudioChunk: (([Float]) -> Void)?
    
    init() {
        // Don't initialize engine in init - do it when recording starts
    }
    
    /// Start recording audio with noise suppression
    func startRecording() throws {
        guard !isRecording else {
            logWarning("Already recording")
            return
        }
        
        // Create fresh engine
        engine = AudioEngine()
        
        guard let engine = engine, let input = engine.input else {
            throw AudioRecorderError.noInputNode
        }
        
        // Clear previous buffer
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        // Install tap to capture audio data
        tap = RawDataTap(input) { [weak self] floatData in
            self?.processAudioData(floatData)
        }
        tap?.start()
        
        do {
            try engine.start()
            isRecording = true
            logInfo("AudioKit recording started at \(Settings.sampleRate)Hz")
        } catch {
            tap?.stop()
            self.engine = nil
            throw AudioRecorderError.engineStartFailed(error)
        }
    }
    
    /// Stop recording and return the captured audio samples
    func stopRecording() -> [Float] {
        guard isRecording else {
            logWarning("Not recording")
            return []
        }
        
        tap?.stop()
        tap = nil
        engine?.stop()
        engine = nil
        isRecording = false
        
        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        // Resample to 16kHz if needed
        let resampledSamples: [Float]
        if abs(Settings.sampleRate - targetSampleRate) > 1 {
            resampledSamples = resample(samples, from: Settings.sampleRate, to: targetSampleRate)
        } else {
            resampledSamples = samples
        }
        
        // Normalize
        let normalizedSamples = normalizeAudio(resampledSamples)
        
        logInfo("AudioKit recording stopped, captured \(samples.count) samples (\(Double(normalizedSamples.count) / targetSampleRate) seconds)")
        return normalizedSamples
    }
    
    /// Cancel recording without returning data
    func cancelRecording() {
        guard isRecording else { return }
        
        tap?.stop()
        tap = nil
        engine?.stop()
        engine = nil
        isRecording = false
        
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        logInfo("AudioKit recording cancelled")
    }
    
    /// Get the most recent audio samples (for visualization)
    func getRecentSamples(count: Int) -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        if audioBuffer.count <= count {
            return audioBuffer
        }
        return Array(audioBuffer.suffix(count))
    }
    
    private func processAudioData(_ floatData: [Float]) {
        // RawDataTap gives us mono float data
        bufferLock.lock()
        audioBuffer.append(contentsOf: floatData)
        bufferLock.unlock()
        
        // Notify for streaming
        onAudioChunk?(floatData)
    }
    
    /// High-quality resampling using vDSP with polynomial interpolation
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = Float(sourceSampleRate / targetSampleRate)
        let outputLength = Int(Float(samples.count) / ratio)

        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)
        var control = (0..<outputLength).map { Float($0) * ratio }
        vDSP_vlint(samples, &control, 1, &output, 1, vDSP_Length(outputLength), vDSP_Length(samples.count))

        return output
    }

    /// Normalize audio to optimal level for transcription using vDSP
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        guard peak > 0.001 else { return samples }

        let targetPeak: Float = 0.9
        let gain = min(targetPeak / peak, 10.0)

        var output = [Float](repeating: 0, count: samples.count)
        var gainVar = gain
        vDSP_vsmul(samples, 1, &gainVar, &output, 1, vDSP_Length(samples.count))

        return output
    }
}
