import Foundation

/// Thread-safe wake-word VAD state used from the audio render callback.
///
/// `WakeWordManager` is `@MainActor`, but audio samples arrive on the audio
/// thread. This store owns listening state, pre-buffer, speech buffer, and VAD
/// counters behind one lock so the render callback does not need actor escapes
/// for ordinary mutable state.
final class WakeWordStateStore: @unchecked Sendable {
    enum IngestResult: Equatable {
        case none
        case debugFrame(count: Int)
        case process(samples: [Float])
    }

    private let lock = NSLock()
    private var listening = false
    private var audioBuffer: [Float] = []
    private var preBuffer: [[Float]] = []
    private var isSpeaking = false
    private var silenceFrames = 0
    private var frameCounter = 0

    func setListening(_ value: Bool) {
        lock.withLock { listening = value }
    }

    func isListening() -> Bool {
        lock.withLock { listening }
    }

    func resetBuffers() {
        lock.withLock {
            audioBuffer.removeAll()
            preBuffer.removeAll()
            isSpeaking = false
            silenceFrames = 0
        }
    }

    func ingest(
        samples: [Float],
        isSpeechFrame: Bool,
        silenceThreshold: Int,
        preBufferFrames: Int,
        maxBufferSamples: Int
    ) -> IngestResult {
        lock.withLock {
            guard listening else { return .none }

            frameCounter += 1
            let shouldDebug = frameCounter % 100 == 1

            preBuffer.append(samples)
            if preBuffer.count > preBufferFrames {
                preBuffer.removeFirst()
            }

            if isSpeechFrame {
                if !isSpeaking {
                    isSpeaking = true
                    silenceFrames = 0
                    for frame in preBuffer {
                        audioBuffer.append(contentsOf: frame)
                    }
                    preBuffer.removeAll()
                }

                audioBuffer.append(contentsOf: samples)
                if audioBuffer.count > maxBufferSamples {
                    audioBuffer.removeFirst(audioBuffer.count - maxBufferSamples)
                }
                silenceFrames = 0
            } else if isSpeaking {
                audioBuffer.append(contentsOf: samples)
                silenceFrames += 1

                if silenceFrames >= silenceThreshold {
                    isSpeaking = false
                    let samplesForProcessing = audioBuffer
                    audioBuffer.removeAll()
                    return .process(samples: samplesForProcessing)
                }
            }

            return shouldDebug ? .debugFrame(count: frameCounter) : .none
        }
    }
}
