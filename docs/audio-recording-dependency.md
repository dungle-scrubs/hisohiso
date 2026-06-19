# Audio recording dependency decision

Decision: keep AudioKit as an optional recorder backend behind the `AudioRecording`
facade.

Rationale:

- The default path remains `AudioRecorder` (`AVAudioEngine`) for the smallest
  dependency surface and fastest local debugging.
- `AudioKitRecorder` is retained because it provides a second recorder backend
  with the same `AudioRecording` contract and a shared `AudioDSP` post-processing
  pipeline.
- Selection is controlled by the `useAudioKit` setting; callers should depend on
  `AudioRecording`, not AudioKit types.
- The default remains `false` because `UserDefaults.bool(for:)` returns false
  until the user explicitly enables AudioKit.

Guardrails:

- `AudioKit` imports stay inside `AudioKitRecorder.swift` and package wiring.
- Tests must keep both recorder implementations conforming to `AudioRecording`.
- New recorder-specific behavior belongs behind the facade or in shared DSP
  utilities, not in `DictationController`.
- Dependency upgrades should be validated with `make validate` because AudioKit
  is a transitive native-audio dependency.

Status: supported optional backend, not experimental dead code.
