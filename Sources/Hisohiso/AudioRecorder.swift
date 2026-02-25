import Accelerate
import AVFoundation
import CoreAudio
import Foundation

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    /// System default device marker
    static let systemDefault = AudioInputDevice(id: 0, name: "System Default", uid: "system_default")

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Error types for audio recording
enum AudioRecorderError: Error, LocalizedError {
    case engineStartFailed(Error)
    case noInputNode
    case permissionDenied
    case notRecording
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case let .engineStartFailed(error):
            "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            "No audio input node available"
        case .permissionDenied:
            "Microphone permission denied"
        case .notRecording:
            "Not currently recording"
        case .deviceNotFound:
            "Selected audio device not found"
        }
    }
}

/// Records audio from the system default input device using AVAudioEngine.
///
/// ## Thread safety
/// All mutable state (`audioBuffer`, `_state`) is protected by `stateLock` (NSLock).
/// Audio tap callbacks run on the audio render thread; public API is called from
/// `@MainActor`. The lock is held only for short reads/writes — never across I/O
/// or engine operations.
final class AudioRecorder: @unchecked Sendable, AudioRecording {
    /// Recorder lifecycle states. Transitions:
    /// `idle` → `monitoring` → `idle`
    /// `idle` → `recording` → `idle`
    /// `monitoring` → `recordingFromMonitoring` → `monitoring` (pause/resume)
    private enum State {
        case idle
        case monitoring
        case recording
        /// Monitoring was active before recording started; resume after stop.
        case recordingFromMonitoring
    }

    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let stateLock = NSLock()
    private var _state: State = .idle

    /// Thread-safe read for current state.
    private var state: State {
        get { stateLock.withLock { _state } }
        set { stateLock.withLock { _state = newValue } }
    }

    /// Target sample rate for WhisperKit (16kHz)
    private let targetSampleRate: Double = AppConstants.targetSampleRate

    /// Currently selected device (nil = system default)
    private var selectedDeviceUID: String?

    /// Called continuously with audio samples when monitoring (for wake word detection)
    var onMonitoringSamples: ((_ samples: [Float], _ sampleRate: Double) -> Void)?

    init() {
        // Load persisted device selection
        selectedDeviceUID = UserDefaults.standard.string(for: .selectedAudioDeviceUID)
    }

    // MARK: - Device Enumeration

    /// Get all available audio input devices
    static func availableInputDevices() -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = [.systemDefault]

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return devices }

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var bufferListSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputChannelsAddress, 0, nil, &bufferListSize)

            guard status == noErr, bufferListSize > 0 else { continue }

            let rawBuffer = UnsafeMutableRawPointer.allocate(
                byteCount: Int(bufferListSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { rawBuffer.deallocate() }

            status = AudioObjectGetPropertyData(deviceID, &inputChannelsAddress, 0, nil, &bufferListSize, rawBuffer)
            guard status == noErr else { continue }

            let bufferListPtr = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }

            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

            guard status == noErr else { continue }

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)

            guard status == noErr else { continue }

            devices.append(AudioInputDevice(
                id: deviceID,
                name: name as String,
                uid: uid as String
            ))
        }

        return devices
    }

    /// Get the currently selected device
    func currentDevice() -> AudioInputDevice {
        guard let uid = selectedDeviceUID else {
            return .systemDefault
        }

        return Self.availableInputDevices().first { $0.uid == uid } ?? .systemDefault
    }

    /// Set the audio input device to use for recording.
    /// - Parameter device: The device to use, or `.systemDefault` for the system default.
    func setInputDevice(_ device: AudioInputDevice) {
        if device.uid == AudioInputDevice.systemDefault.uid {
            selectedDeviceUID = nil
            UserDefaults.standard.remove(for: .selectedAudioDeviceUID)
        } else {
            selectedDeviceUID = device.uid
            UserDefaults.standard.set(device.uid, for: .selectedAudioDeviceUID)
        }
        logInfo("Audio input device set to: \(device.name)")
    }

    /// Apply the selected device to the audio engine
    private func applySelectedDevice() throws {
        guard let uid = selectedDeviceUID else {
            // Use system default - no need to set anything
            return
        }

        // Find device by UID
        let devices = Self.availableInputDevices()
        guard let device = devices.first(where: { $0.uid == uid }), device.id != 0 else {
            logWarning("Selected device not found, using system default")
            return
        }

        // Set the device on the audio unit
        var deviceID = device.id
        guard let audioUnit = engine.inputNode.audioUnit else {
            logError("Audio unit unavailable for input node")
            throw AudioRecorderError.noInputNode
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logError("Failed to set audio device: \(status)")
            throw AudioRecorderError.deviceNotFound
        }

        logInfo("Applied audio device: \(device.name)")
    }

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

    /// Start recording audio from the selected input device.
    /// Installs an audio tap on the input node and captures samples at 16kHz mono.
    /// - Throws: `AudioRecorderError` if the engine fails to start or no input is available.
    func startRecording() throws {
        logInfo("AudioRecorder.startRecording() called (state: \(state))")

        let currentState = state
        guard currentState == .idle || currentState == .monitoring else {
            logWarning("Already recording, returning early")
            return
        }

        // Stop monitoring if active (can't have two taps on same node)
        if currentState == .monitoring {
            logInfo("Stopping monitoring tap before recording...")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            logInfo("Monitoring paused for recording")
        }

        // No VPIO — it adds ~1.5s latency per recording start and corrupts
        // the audio unit state when toggling between monitoring/recording.
        // Noise handling is done post-capture via the DSP pipeline instead
        // (high-pass filter + VAD silence trimming + normalization).
        try applySelectedDevice()

        let inputNode = engine.inputNode
        let (tapFormat, sampleRate) = try monoTapFormat()

        logInfo("Recording at \(sampleRate)Hz")

        // Clear previous buffer
        stateLock.lock()
        audioBuffer.removeAll()
        stateLock.unlock()

        // Install tap with explicit mono format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputSampleRate: sampleRate)
        }

        do {
            try engine.start()
            state = currentState == .monitoring ? .recordingFromMonitoring : .recording
            logInfo("Recording started")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Create an explicit mono Float32 format at the hardware sample rate.
    /// VPIO can report unusual channel counts; a mono tap format avoids this.
    /// - Returns: Tuple of (tap format, sample rate).
    /// - Throws: `AudioRecorderError.noInputNode` if no valid sample rate.
    private func monoTapFormat() throws -> (AVAudioFormat, Double) {
        let hardwareFormat = engine.inputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48000

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.noInputNode
        }

        return (format, sampleRate)
    }

    /// Stop recording and return the captured audio.
    /// - Returns: Audio samples resampled to 16kHz mono and normalized, or empty if not recording.
    func stopRecording() -> [Float] {
        let currentState = state
        guard currentState == .recording || currentState == .recordingFromMonitoring else {
            logWarning("Not recording")
            return []
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = currentState == .recordingFromMonitoring ? .monitoring : .idle

        stateLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        stateLock.unlock()

        // Noise-handling pipeline: high-pass filter → trim silence → normalize.
        // Voice processing (VPIO) already cleaned the signal during capture;
        // these post-processing steps remove residual sub-bass rumble and
        // trim leading/trailing silence to prevent model hallucinations.
        let filtered = AudioDSP.highPassFilter(samples)
        let trimmed = AudioDSP.trimSilence(filtered)
        let normalizedSamples = AudioDSP.normalize(trimmed)

        logInfo(
            "Recording stopped: \(samples.count) raw → \(normalizedSamples.count) processed samples (\(String(format: "%.1f", Double(normalizedSamples.count) / targetSampleRate))s)"
        )
        return normalizedSamples
    }

    /// Cancel recording without returning data
    func cancelRecording() {
        let currentState = state
        guard currentState == .recording || currentState == .recordingFromMonitoring else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = currentState == .recordingFromMonitoring ? .monitoring : .idle

        stateLock.lock()
        audioBuffer.removeAll()
        stateLock.unlock()

        logInfo("Recording cancelled")
    }

    // MARK: - Monitoring Mode (for wake word detection)

    /// Start continuous audio monitoring for wake word detection.
    /// Samples are delivered to the `onMonitoringSamples` callback.
    /// - Throws: `AudioRecorderError` if the engine fails to start.
    func startMonitoring() throws {
        guard state == .idle else {
            logDebug("Already monitoring or recording")
            return
        }

        try applySelectedDevice()

        let (tapFormat, tapSampleRate) = try monoTapFormat()

        logInfo("Starting audio monitoring at \(tapSampleRate)Hz")

        // Install tap for monitoring
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            self?.processMonitoringBuffer(buffer, sampleRate: tapSampleRate)
        }

        do {
            try engine.start()
            state = .monitoring
            logInfo("Audio monitoring started")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Stop audio monitoring
    func stopMonitoring() {
        guard state == .monitoring else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .idle
        logInfo("Audio monitoring stopped")
    }

    /// Pause monitoring (when recording starts)
    func pauseMonitoring() {
        guard state == .monitoring else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // State stays .monitoring — startRecording() reads it to decide .recordingFromMonitoring
        logDebug("Audio monitoring paused")
    }

    /// Resume monitoring (after recording stops)
    func resumeMonitoring() {
        guard state == .monitoring else { return }

        do {
            let (tapFormat, tapSampleRate) = try monoTapFormat()

            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
                self?.processMonitoringBuffer(buffer, sampleRate: tapSampleRate)
            }

            try engine.start()
            logDebug("Audio monitoring resumed")
        } catch {
            logError("Failed to resume monitoring, resetting to idle: \(error)")
            state = .idle
        }
    }

    private func processMonitoringBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        // Send to callback
        onMonitoringSamples?(samples, sampleRate)
    }

    /// Get the most recent audio samples from the recording buffer.
    /// - Parameter count: Maximum number of samples to return.
    /// - Returns: Most recent samples, or fewer if not enough have been recorded.
    func getRecentSamples(count: Int) -> [Float] {
        stateLock.lock()
        defer { stateLock.unlock() }

        if audioBuffer.count <= count {
            return audioBuffer
        }
        return Array(audioBuffer.suffix(count))
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
        let resampledSamples: [Float] = if abs(inputSampleRate - targetSampleRate) > 1 {
            resample(monoSamples, from: inputSampleRate, to: targetSampleRate)
        } else {
            monoSamples
        }

        stateLock.lock()
        audioBuffer.append(contentsOf: resampledSamples)
        stateLock.unlock()
    }

    /// Resample audio using shared DSP utility.
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        AudioDSP.resample(samples, from: sourceSampleRate, to: targetSampleRate)
    }
}
