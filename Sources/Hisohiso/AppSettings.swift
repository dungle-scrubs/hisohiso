import Carbon.HIToolbox
import Foundation

// MARK: - UserDefaults Keys

/// Centralized registry of all UserDefaults keys.
///
/// Eliminates scattered string literals and provides compile-time safety.
/// Every UserDefaults read/write in the app must use a key from this enum.
enum SettingsKey: String {
    // Audio
    case selectedAudioDeviceUID
    case audioFeedbackEnabled
    case useAudioKit

    // Model
    case selectedModel

    // Hotkey
    case alternativeHotkey

    // Wake word
    case wakeWordEnabled
    case wakePhrase

    // Sinew / UI
    case useSinewVisualization
    case showFloatingPill

    // Voice verification
    case voiceVerificationEnabled
    case voiceVerificationThreshold

    // Cloud
    case cloudFallbackEnabled
    case cloudFallbackProvider

    // Text formatting
    case fillerWords

    // Onboarding
    case hasCompletedOnboarding
}

// MARK: - UserDefaults Typed Accessors

extension UserDefaults {
    /// Read a Bool with a `SettingsKey`.
    func bool(for key: SettingsKey) -> Bool {
        bool(forKey: key.rawValue)
    }

    /// Write a Bool with a `SettingsKey`.
    func set(_ value: Bool, for key: SettingsKey) {
        set(value, forKey: key.rawValue)
    }

    /// Read an optional String with a `SettingsKey`.
    func string(for key: SettingsKey) -> String? {
        string(forKey: key.rawValue)
    }

    /// Write a String with a `SettingsKey`.
    func set(_ value: String, for key: SettingsKey) {
        set(value, forKey: key.rawValue)
    }

    /// Read an optional String array with a `SettingsKey`.
    func stringArray(for key: SettingsKey) -> [String]? {
        stringArray(forKey: key.rawValue)
    }

    /// Read optional Data with a `SettingsKey`.
    func data(for key: SettingsKey) -> Data? {
        data(forKey: key.rawValue)
    }

    /// Write Data with a `SettingsKey`.
    func set(_ value: Data, for key: SettingsKey) {
        set(value, forKey: key.rawValue)
    }

    /// Read a Double with a `SettingsKey`.
    func double(for key: SettingsKey) -> Double {
        double(forKey: key.rawValue)
    }

    /// Write a Double with a `SettingsKey`.
    func set(_ value: Double, for key: SettingsKey) {
        set(value, forKey: key.rawValue)
    }

    /// Check if a key has ever been written (not nil).
    func hasValue(for key: SettingsKey) -> Bool {
        object(forKey: key.rawValue) != nil
    }

    /// Remove a key.
    func remove(for key: SettingsKey) {
        removeObject(forKey: key.rawValue)
    }
}

// MARK: - App Constants

/// App-wide numeric and timing constants.
///
/// Centralizes magic numbers that were previously scattered inline.
enum AppConstants {
    /// Audio sample rate expected by transcription models (Hz).
    static let targetSampleRate: Double = 16000

    /// Minimum audio samples for a valid transcription (1 second at 16kHz).
    static let minTranscriptionSamples = 16000

    /// Globe key hold threshold to distinguish tap from hold (seconds).
    static let globeHoldThreshold: TimeInterval = 0.3

    /// Recording timeout before showing an error (seconds).
    static let transcriptionTimeout: TimeInterval = 30

    /// Delay before restoring clipboard after Cmd+V paste insertion (seconds).
    static let pasteRestoreDelay: TimeInterval = 0.5

    /// Maximum text length for direct character-by-character insertion.
    /// Longer text uses clipboard paste.
    static let directInsertionThreshold = 10

    /// Audio level update interval for waveform visualization (seconds).
    static let audioLevelUpdateInterval: TimeInterval = 0.05

    /// Error auto-dismiss delay for floating pill (seconds).
    static let errorAutoDismissDelay: TimeInterval = 3.0

    /// Number of waveform bars in audio visualization.
    static let waveformBarCount = 7

    /// Audio level multiplier for waveform display normalization.
    static let audioLevelMultiplier: Float = 800

    // MARK: - Key Codes

    /// Virtual key code for Escape.
    static let escapeKeyCode: UInt16 = UInt16(kVK_Escape)

    /// Virtual key code for V (used in Cmd+V paste simulation).
    static let vKeyCode: UInt16 = UInt16(kVK_ANSI_V)

    // MARK: - Wake Word

    /// Default wake phrase for voice activation.
    static let defaultWakePhrase = "hey hisohiso"

    /// Minimum audio samples for wake word processing (0.5 seconds at 16kHz).
    static let minWakeWordSamples = 8000

    /// Maximum wake word audio buffer size (~3 seconds at 16kHz).
    static let maxWakeWordBufferSamples = 48000

    /// VAD speech RMS threshold for wake word detection.
    static let wakeWordSpeechThreshold: Float = 0.015

    /// Number of silence frames before ending wake word speech segment.
    static let wakeWordSilenceFrames = 10

    /// Number of pre-buffer frames to keep before speech detection.
    static let wakeWordPreBufferFrames = 5

    // MARK: - Silence Detection (Wake Word Auto-Stop)

    /// Silence frame count before auto-stopping a wake-word-triggered recording.
    static let silenceThresholdForStop = 25

    /// RMS threshold below which audio is considered silence.
    static let silenceRMSThreshold: Float = 0.01

    /// Grace period frames before silence detection activates (3 seconds at 50ms/frame).
    static let silenceGracePeriodFrames = 60

    // MARK: - Voice Verification

    /// Minimum audio samples for speaker verification (2 seconds at 16kHz).
    static let minVoiceVerificationSamples = 32000

    /// Default voice verification similarity threshold.
    static let defaultVoiceVerificationThreshold: Float = 0.75

    // MARK: - Logging

    /// Maximum age in days for log files before cleanup.
    static let maxLogAgeDays = 14

    // MARK: - Debug

    /// Maximum number of debug audio files to keep.
    static let maxDebugAudioFiles = 10
}
