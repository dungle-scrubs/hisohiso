import Foundation

protocol VoiceEnrollmentVerifying: AnyObject, Sendable {
    func enroll(with samples: [[Float]]) async throws -> [Float]
}

extension VoiceVerifier: VoiceEnrollmentVerifying {}

@MainActor
final class VoiceEnrollmentController {
    struct DebugInfo: Equatable {
        let sessionID: Int
        let status: Status
        let capturedSampleCount: Int
        let isRecording: Bool
        let hasRecorder: Bool
        let hasEnrollmentTask: Bool
    }

    enum Status: Equatable {
        case idle
        case recording(sampleCount: Int)
        case processing
        case completed
        case failed(FailureReason)
    }

    enum FailureReason: Equatable {
        case noAudioCaptured
        case microphoneUnavailable
        case enrollmentFailed(String)
    }

    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .idle {
        didSet {
            onStatusChange?(status)
            assertStateInvariant()
        }
    }

    private static let targetSampleCount = 3

    private var enrollmentSamples: [[Float]] = []
    private var recorder: AudioRecording?
    private var isRecording = false
    private var enrollmentTask: Task<Void, Never>?
    private var sessionID = 0
    private let verifier: VoiceEnrollmentVerifying
    private let recorderFactory: () -> AudioRecording
    private let sampleDuration: TimeInterval
    private let debugLogging: Bool

    init(
        verifier: VoiceEnrollmentVerifying = VoiceVerifier.shared,
        recorderFactory: @escaping () -> AudioRecording = {
            AppPreferences.shared.useAudioKit ? AudioKitRecorder() : AudioRecorder()
        },
        sampleDuration: TimeInterval = 2.5,
        debugLogging: Bool = false
    ) {
        self.verifier = verifier
        self.recorderFactory = recorderFactory
        self.sampleDuration = sampleDuration
        self.debugLogging = debugLogging
    }

    func start() {
        logInfo("VoiceEnrollmentController.start session=\(sessionID + 1) previousStatus=\(status.logValue)")
        cancelEnrollmentTask()
        sessionID += 1
        enrollmentSamples = []
        isRecording = true
        recorder = recorderFactory()
        status = .recording(sampleCount: 0)
        collectEnrollmentSample(sessionID: sessionID)
        logInfo("VoiceEnrollmentController.start complete session=\(sessionID) status=\(status.logValue)")
    }

    func stop() {
        logInfo("VoiceEnrollmentController.stop session=\(sessionID) status=\(status.logValue)")
        isRecording = false
        captureCurrentSample()
        finishEnrollment(sessionID: sessionID)
        logInfo("VoiceEnrollmentController.stop complete session=\(sessionID) status=\(status.logValue)")
    }

    func cancel() {
        logInfo("VoiceEnrollmentController.cancel session=\(sessionID) status=\(status.logValue)")
        sessionID += 1
        isRecording = false
        recorder?.cancelRecording()
        recorder = nil
        enrollmentSamples = []
        cancelEnrollmentTask()
        status = .idle
        logInfo("VoiceEnrollmentController.cancel complete session=\(sessionID) status=\(status.logValue)")
    }

    func debugInfo() -> DebugInfo {
        DebugInfo(
            sessionID: sessionID,
            status: status,
            capturedSampleCount: enrollmentSamples.count,
            isRecording: isRecording,
            hasRecorder: recorder != nil,
            hasEnrollmentTask: enrollmentTask != nil
        )
    }

    /// Wait for the in-flight enrollment, if any, to settle into `.completed` or `.failed`.
    ///
    /// `status` moves to its final value on the enrollment task after the verifier
    /// returns, so observers that only wait for the verifier call can still see
    /// `.processing`. Awaiting this closes that gap.
    func awaitEnrollment() async {
        await enrollmentTask?.value
    }

    private func finishEnrollment(sessionID: Int) {
        guard !enrollmentSamples.isEmpty else {
            logWarning("VoiceEnrollmentController.finish failed session=\(sessionID) reason=noAudioCaptured")
            status = .failed(.noAudioCaptured)
            return
        }

        status = .processing
        let samples = enrollmentSamples
        enrollmentSamples = []
        traceDebug("VoiceEnrollmentController.finish processing session=\(sessionID) samples=\(samples.count)")

        enrollmentTask = Task { @MainActor [weak self, verifier] in
            do {
                _ = try await verifier.enroll(with: samples)
                guard !Task.isCancelled, self?.sessionID == sessionID else {
                    self?.traceDebug("VoiceEnrollmentController.finish ignored stale completion session=\(sessionID)")
                    return
                }
                self?.enrollmentTask = nil
                logInfo("VoiceEnrollmentController.finish completed session=\(sessionID) samples=\(samples.count)")
                self?.status = .completed
            } catch {
                guard !Task.isCancelled, self?.sessionID == sessionID else {
                    self?.traceDebug("VoiceEnrollmentController.finish ignored stale failure session=\(sessionID)")
                    return
                }
                self?.enrollmentTask = nil
                logError(
                    "VoiceEnrollmentController.finish failed session=\(sessionID) error=\(error.localizedDescription)"
                )
                self?.status = .failed(.enrollmentFailed(error.localizedDescription))
            }
        }
    }

    private func captureCurrentSample() {
        if let samples = recorder?.stopRecording(), samples.count >= VoiceVerifier.minSamplesForVerification {
            enrollmentSamples.append(samples)
            traceDebug(
                "VoiceEnrollmentController.capture sampleAccepted session=\(sessionID) samples=\(enrollmentSamples.count) sampleCount=\(samples.count)"
            )
        } else {
            traceDebug("VoiceEnrollmentController.capture sampleRejected session=\(sessionID)")
        }
        recorder = nil
    }

    private func collectEnrollmentSample(sessionID: Int) {
        guard isRecording, let recorder else { return }

        do {
            try recorder.startRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + sampleDuration) { [weak self, weak recorder] in
                guard let self, isRecording, self.sessionID == sessionID, let recorder else {
                    self?.traceDebug("VoiceEnrollmentController.collect ignored stale timer session=\(sessionID)")
                    return
                }

                let samples = recorder.stopRecording()
                if samples.count >= VoiceVerifier.minSamplesForVerification {
                    enrollmentSamples.append(samples)
                    status = .recording(sampleCount: enrollmentSamples.count)
                    traceDebug(
                        "VoiceEnrollmentController.collect sampleAccepted session=\(sessionID) samples=\(enrollmentSamples.count) sampleCount=\(samples.count)"
                    )
                } else {
                    traceDebug(
                        "VoiceEnrollmentController.collect sampleRejected session=\(sessionID) sampleCount=\(samples.count)"
                    )
                }

                if enrollmentSamples.count < Self.targetSampleCount {
                    collectEnrollmentSample(sessionID: sessionID)
                } else {
                    self.recorder = nil
                    isRecording = false
                    finishEnrollment(sessionID: sessionID)
                }
            }
        } catch {
            logError("Failed to start enrollment recording: \(error)")
            isRecording = false
            self.recorder = nil
            status = .failed(.microphoneUnavailable)
        }
    }

    private func cancelEnrollmentTask() {
        enrollmentTask?.cancel()
        enrollmentTask = nil
    }

    private func traceDebug(_ message: String) {
        guard debugLogging else { return }
        logDebug(message)
    }

    private func assertStateInvariant() {
        assert(enrollmentSamples.count <= Self.targetSampleCount, "Voice enrollment captured too many samples")
        switch status {
        case .idle, .completed, .failed:
            assert(!isRecording, "Voice enrollment terminal state cannot still be recording")
        case let .recording(sampleCount):
            assert(isRecording, "Voice enrollment recording state requires active recording")
            assert(sampleCount == enrollmentSamples.count, "Voice enrollment status sample count drifted")
        case .processing:
            assert(!isRecording, "Voice enrollment processing state cannot still be recording")
        }
    }
}

private extension VoiceEnrollmentController.Status {
    var logValue: String {
        switch self {
        case .idle:
            "idle"
        case let .recording(sampleCount):
            "recording(sampleCount=\(sampleCount))"
        case .processing:
            "processing"
        case .completed:
            "completed"
        case let .failed(reason):
            "failed(reason=\(reason.logValue))"
        }
    }
}

private extension VoiceEnrollmentController.FailureReason {
    var logValue: String {
        switch self {
        case .noAudioCaptured:
            "noAudioCaptured"
        case .microphoneUnavailable:
            "microphoneUnavailable"
        case let .enrollmentFailed(message):
            "enrollmentFailed(\(message))"
        }
    }
}
