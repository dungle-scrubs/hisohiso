import Accelerate
import Foundation

/// Publishes recorder audio levels and wake-word silence decisions.
///
/// `DictationController` owns the recording state machine. This publisher owns
/// the timer-driving policy for recent sample reads, level fanout, and optional
/// silence auto-stop detection.
@MainActor
final class AudioLevelPublisher {
    typealias SampleProvider = () -> [Float]
    typealias LevelSink = ([UInt8]) -> Void
    typealias AutoStop = () -> Void

    private var timer: Timer?
    private var isWakeWordTriggered = false
    private var silenceFrameCount = 0
    private var gracePeriodFrames = 0

    private let sampleProvider: SampleProvider
    private let levelSink: LevelSink
    private let autoStop: AutoStop

    init(sampleProvider: @escaping SampleProvider, levelSink: @escaping LevelSink, autoStop: @escaping AutoStop) {
        self.sampleProvider = sampleProvider
        self.levelSink = levelSink
        self.autoStop = autoStop
    }

    func start(isWakeWordTriggered: Bool) {
        stop()
        self.isWakeWordTriggered = isWakeWordTriggered
        silenceFrameCount = 0
        gracePeriodFrames = 0
        timer = Timer.scheduledTimer(withTimeInterval: AppConstants.audioLevelUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clearLevels() {
        levelSink([UInt8](repeating: 0, count: AppConstants.waveformBarCount))
    }

    func tick() {
        let samples = sampleProvider()
        levelSink(AudioLevelPublisher.calculateAudioLevels(from: samples))
        if isWakeWordTriggered {
            checkSilenceForAutoStop(samples: samples)
        }
    }

    /// Calculate waveform levels from audio samples using Accelerate.
    /// - Parameter samples: Raw audio samples (16kHz mono).
    /// - Returns: Array of 7 normalized levels (0–100).
    static func calculateAudioLevels(from samples: [Float]) -> [UInt8] {
        let numBars = AppConstants.waveformBarCount
        guard !samples.isEmpty else {
            return [UInt8](repeating: 0, count: numBars)
        }

        let chunkSize = max(1, samples.count / numBars)
        var levels = [UInt8]()
        levels.reserveCapacity(numBars)

        for i in 0..<numBars {
            let start = i * chunkSize
            guard start < samples.count else {
                levels.append(0)
                continue
            }

            let end = min(start + chunkSize, samples.count)
            let count = end - start

            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + start, 1, &rms, vDSP_Length(count))
            }

            // Sqrt compression: boosts quiet speech, prevents loud sounds from clipping
            let linear = rms * AppConstants.audioLevelMultiplier
            let compressed = sqrt(linear) * 10.0
            let normalized = min(100, max(0, Int(compressed)))
            levels.append(UInt8(normalized))
        }

        return levels
    }

    private func checkSilenceForAutoStop(samples: [Float]) {
        guard !samples.isEmpty else { return }
        gracePeriodFrames += 1
        guard gracePeriodFrames >= AppConstants.silenceGracePeriodFrames else { return }

        let rms = AudioLevelPublisher.rms(samples)
        if rms < AppConstants.silenceRMSThreshold {
            silenceFrameCount += 1
            if silenceFrameCount >= AppConstants.silenceThresholdForStop {
                logInfo("Wake word recording: auto-stopping after \(silenceFrameCount) frames of silence")
                autoStop()
            }
        } else {
            silenceFrameCount = 0
        }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }
}
