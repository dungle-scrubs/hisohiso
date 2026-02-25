@testable import Hisohiso
import XCTest

final class AppSettingsTests: XCTestCase {
    /// Unique suite name to avoid polluting real UserDefaults.
    private let suiteName = "com.hisohiso.tests.settings-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - SettingsKey Uniqueness

    func testAllSettingsKeysAreUnique() {
        // Compile-time guarantee via enum, but verify raw values are distinct.
        let allKeys: [SettingsKey] = [
            .selectedAudioDeviceUID, .audioFeedbackEnabled, .useAudioKit,
            .selectedModel, .alternativeHotkey,
            .wakeWordEnabled, .wakePhrase,
            .useSinewVisualization, .showFloatingPill,
            .voiceVerificationEnabled, .voiceVerificationThreshold,
            .cloudFallbackEnabled, .cloudFallbackProvider,
            .fillerWords, .hasCompletedOnboarding,
        ]

        let rawValues = allKeys.map(\.rawValue)
        let uniqueRawValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueRawValues.count, "Duplicate SettingsKey raw values found")
    }

    // MARK: - Typed Accessors

    func testBoolAccessor() {
        defaults.set(true, forKey: SettingsKey.audioFeedbackEnabled.rawValue)
        XCTAssertTrue(defaults.bool(for: .audioFeedbackEnabled))

        defaults.set(false, forKey: SettingsKey.audioFeedbackEnabled.rawValue)
        XCTAssertFalse(defaults.bool(for: .audioFeedbackEnabled))
    }

    func testBoolWriteAccessor() {
        defaults.set(true, for: .audioFeedbackEnabled)
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.audioFeedbackEnabled.rawValue))
    }

    func testStringAccessor() {
        defaults.set("test-device", forKey: SettingsKey.selectedAudioDeviceUID.rawValue)
        XCTAssertEqual(defaults.string(for: .selectedAudioDeviceUID), "test-device")
    }

    func testStringAccessorReturnsNilWhenMissing() {
        XCTAssertNil(defaults.string(for: .selectedAudioDeviceUID))
    }

    func testHasValueAccessor() {
        XCTAssertFalse(defaults.hasValue(for: .audioFeedbackEnabled))
        defaults.set(false, forKey: SettingsKey.audioFeedbackEnabled.rawValue)
        XCTAssertTrue(defaults.hasValue(for: .audioFeedbackEnabled))
    }

    func testRemoveAccessor() {
        defaults.set("value", forKey: SettingsKey.selectedModel.rawValue)
        XCTAssertTrue(defaults.hasValue(for: .selectedModel))

        defaults.remove(for: .selectedModel)
        XCTAssertFalse(defaults.hasValue(for: .selectedModel))
    }

    func testDoubleAccessor() {
        defaults.set(0.75, for: .voiceVerificationThreshold)
        XCTAssertEqual(defaults.double(for: .voiceVerificationThreshold), 0.75, accuracy: 0.001)
    }

    func testDataAccessor() {
        let data = Data([1, 2, 3, 4])
        defaults.set(data, for: .alternativeHotkey)
        XCTAssertEqual(defaults.data(for: .alternativeHotkey), data)
    }

    // MARK: - AppConstants

    func testConstantsAreReasonable() {
        XCTAssertEqual(AppConstants.targetSampleRate, 16000)
        XCTAssertEqual(AppConstants.minTranscriptionSamples, 16000)
        XCTAssertGreaterThan(AppConstants.transcriptionTimeout, 0)
        XCTAssertGreaterThan(AppConstants.globeHoldThreshold, 0)
        XCTAssertLessThan(AppConstants.globeHoldThreshold, 1.0)
        XCTAssertGreaterThan(AppConstants.waveformBarCount, 0)
        XCTAssertGreaterThan(AppConstants.maxLogAgeDays, 0)
    }
}
