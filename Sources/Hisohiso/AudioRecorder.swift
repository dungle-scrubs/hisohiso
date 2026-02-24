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
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            return "No audio input node available"
        case .permissionDenied:
            return "Microphone permission denied"
        case .notRecording:
            return "Not currently recording"
        case .deviceNotFound:
            return "Selected audio device not found"
        }
    }
}

/// Records audio from the system default input device using AVAudioEngine.
///
/// ## Thread safety
/// All mutable state (`audioBuffer`, `isRecording`, `isMonitoring`) is protected by
/// `stateLock` (NSLock). Audio tap callbacks run on the audio render thread; public
/// API is called from `@MainActor`. The lock is held only for short reads/writes —
/// never across I/O or engine operations.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let stateLock = NSLock()
    private var _isRecording = false
    private var _isMonitoring = false

    /// Thread-safe read for recording state.
    private var isRecording: Bool {
        get { stateLock.withLock { _isRecording } }
        set { stateLock.withLock { _isRecording = newValue } }
    }

    /// Thread-safe read for monitoring state.
    private var isMonitoring: Bool {
        get { stateLock.withLock { _isMonitoring } }
        set { stateLock.withLock { _isMonitoring = newValue } }
    }

    /// Target sample rate for WhisperKit (16kHz)
    private let targetSampleRate: Double = 16000

    /// Currently selected device (nil = system default)
    private var selectedDeviceUID: String?

    /// Called continuously with audio samples when monitoring (for wake word detection)
    var onMonitoringSamples: ((_ samples: [Float], _ sampleRate: Double) -> Void)?

    /// UserDefaults key for persisted device selection
    private static let selectedDeviceKey = "selectedAudioDeviceUID"

    init() {
        // Load persisted device selection
        selectedDeviceUID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
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

    /// Set the input device to use
    func setInputDevice(_ device: AudioInputDevice) {
        if device.uid == AudioInputDevice.systemDefault.uid {
            selectedDeviceUID = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedDeviceKey)
        } else {
            selectedDeviceUID = device.uid
            UserDefaults.standard.set(device.uid, forKey: Self.selectedDeviceKey)
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

    /// Start recording audio
    /// - Throws: AudioRecorderError if recording fails to start
    func startRecording() throws {
        logInfo("AudioRecorder.startRecording() called (isRecording: \(isRecording), isMonitoring: \(isMonitoring))")
        
        guard !isRecording else {
            logWarning("Already recording, returning early")
            return
        }

        // Stop monitoring if active (can't have two taps on same node)
        if isMonitoring {
            logInfo("Stopping monitoring tap before recording...")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            // Keep isMonitoring true so we resume after recording
            logInfo("Monitoring paused for recording")
        }

        // Apply selected device before getting input format
        try applySelectedDevice()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.noInputNode
        }

        logInfo("Starting recording at \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Clear previous buffer
        stateLock.lock()
        audioBuffer.removeAll()
        stateLock.unlock()

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
    /// - Returns: Audio samples resampled to 16kHz mono, normalized
    func stopRecording() -> [Float] {
        guard isRecording else {
            logWarning("Not recording")
            return []
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        stateLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        stateLock.unlock()

        // Normalize audio levels for better transcription
        let normalizedSamples = normalizeAudio(samples)

        logInfo("Recording stopped, captured \(samples.count) samples (\(Double(samples.count) / targetSampleRate) seconds)")
        return normalizedSamples
    }

    /// Cancel recording without returning data
    func cancelRecording() {
        guard isRecording else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        stateLock.lock()
        audioBuffer.removeAll()
        stateLock.unlock()

        logInfo("Recording cancelled")
    }
    
    // MARK: - Monitoring Mode (for wake word detection)
    
    /// Start continuous audio monitoring without recording
    /// Audio samples are sent to `onMonitoringSamples` callback
    func startMonitoring() throws {
        guard !isMonitoring && !isRecording else {
            logDebug("Already monitoring or recording")
            return
        }
        
        try applySelectedDevice()
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.noInputNode
        }
        
        logInfo("Starting audio monitoring at \(inputFormat.sampleRate)Hz")
        
        // Install tap for monitoring
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processMonitoringBuffer(buffer, sampleRate: inputFormat.sampleRate)
        }
        
        do {
            try engine.start()
            isMonitoring = true
            logInfo("Audio monitoring started")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
    }
    
    /// Stop audio monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
        logInfo("Audio monitoring stopped")
    }
    
    /// Pause monitoring (when recording starts)
    func pauseMonitoring() {
        guard isMonitoring else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Keep isMonitoring true so we know to resume
        logDebug("Audio monitoring paused")
    }
    
    /// Resume monitoring (after recording stops)
    func resumeMonitoring() {
        guard isMonitoring && !isRecording else { return }
        
        do {
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.processMonitoringBuffer(buffer, sampleRate: inputFormat.sampleRate)
            }
            
            try engine.start()
            logDebug("Audio monitoring resumed")
        } catch {
            logError("Failed to resume monitoring: \(error)")
        }
    }
    
    private func processMonitoringBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        
        // Send to callback
        onMonitoringSamples?(samples, sampleRate)
    }

    /// Get the most recent audio samples (for visualization)
    /// - Parameter count: Number of samples to return
    /// - Returns: Most recent samples (or fewer if not enough recorded)
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
        let resampledSamples: [Float]
        if abs(inputSampleRate - targetSampleRate) > 1 {
            resampledSamples = resample(monoSamples, from: inputSampleRate, to: targetSampleRate)
        } else {
            resampledSamples = monoSamples
        }

        stateLock.lock()
        audioBuffer.append(contentsOf: resampledSamples)
        stateLock.unlock()
    }

    /// Resample audio using shared DSP utility.
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        AudioDSP.resample(samples, from: sourceSampleRate, to: targetSampleRate)
    }

    /// Normalize audio using shared DSP utility.
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        AudioDSP.normalize(samples)
    }
}
