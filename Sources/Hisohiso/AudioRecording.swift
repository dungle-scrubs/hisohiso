import Foundation

/// Unified recording interface for audio capture backends.
///
/// Both `AudioRecorder` (AVAudioEngine) and `AudioKitRecorder` (AudioKit)
/// conform to this protocol, eliminating duplicated dispatch logic in
/// `DictationController`.
protocol AudioRecording: AnyObject {
    /// Start capturing audio from the selected input device.
    /// - Throws: `AudioRecorderError` if the engine fails to start.
    func startRecording() throws

    /// Stop capturing and return the processed audio samples.
    /// - Returns: Audio samples resampled to 16kHz mono and normalized.
    func stopRecording() -> [Float]

    /// Cancel recording without returning data.
    func cancelRecording()

    /// Get the most recent audio samples from the recording buffer.
    /// - Parameter count: Maximum number of samples to return.
    /// - Returns: Most recent samples, or fewer if not enough have been recorded.
    func getRecentSamples(count: Int) -> [Float]
}
