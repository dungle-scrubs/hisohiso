# Hisohiso

Local-first macOS dictation app using WhisperKit, activated by Globe key.

## Design Decisions

| Category | Decision |
|----------|----------|
| Distribution | Direct (notarized DMG), not App Store |
| macOS target | 13 Ventura+ (Apple Silicon required) |
| Transcription | Streaming (text appears as you speak) |
| Default model | Parakeet v2 (English), download on demand |
| Model storage | ~/Library/Application Support/Hisohiso |
| Cloud | Optional fallback (OpenAI, Groq), API keys in Keychain |
| Recording indicator | Floating pill (v0.1-v0.3), RustyBar IPC (v0.4+) |
| Menu bar | Minimal (icon only, click→prefs, right-click→quit) |
| Text formatting | Smart local rules (capitalize, punctuation, remove filler words) |
| History | SwiftData, kept forever, accessible via RustyBar popup |
| Hotkey | Globe key + configurable alternative (modifier-only supported) |
| Audio feedback | Subtle click sounds on start/stop |
| Auto-launch | Default on (login item) |
| Onboarding | Single checklist screen |
| Audio input | System default only |
| Timeout | 10 seconds, show error, offer retry |
| Testing | Unit + Integration (XCTest) |
| Crash reporting | Sentry (production only) |
| Error display | Floating pill with error state + retry button |
| Timeout retry | Retry button in floating pill |
| Menu bar icon | Waveform |
| Filler words | Editable in preferences |
| Bundle ID | com.{yourname}.hisohiso |
| Auto-updates | Sparkle + GitHub Releases |
| Design | Minimalist - clean, unobtrusive, no unnecessary chrome |

## Tech Stack

- Swift 5.9+, SwiftUI, SwiftData
- WhisperKit for on-device transcription (default: Parakeet v2)
- CGEventTap for global hotkey capture
- AVAudioEngine for audio capture
- CoreML speaker embedding model for voice verification (v0.5)
- Sentry for crash reporting (production)

## Build & Run

```bash
swift build
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Pre-commit Hooks

```bash
brew install swiftlint swiftformat pre-commit
pre-commit install
```

Hooks run: SwiftFormat → SwiftLint → swift build (type check)

## Dev Logging

Logs write to `~/Library/Logs/Hisohiso/` for LLM consumption during debugging.

```bash
# Tail logs in a separate terminal
tail -f ~/Library/Logs/Hisohiso/hisohiso-*.log
```

Then ask Claude: "Check the log output and help me debug this issue"

## Requirements

- macOS 13 Ventura+
- Apple Silicon (M1+) for WhisperKit Neural Engine acceleration
- Accessibility permission (for global hotkey + text insertion)
- Input Monitoring permission (for keyboard events)
- Microphone permission

## RustyBar Integration

See [RUSTYBAR_INTEGRATION.md](./RUSTYBAR_INTEGRATION.md) for:
- IPC protocol (`set hisohiso <state>`)
- Rust module implementation
- History popup support
- Config examples

## Key Files

- `GlobeKeyMonitor.swift` - CGEventTap monitoring for Globe/Fn key
- `HotkeyManager.swift` - Globe + configurable alternative hotkey
- `AudioRecorder.swift` - AVAudioEngine audio capture
- `AudioFeedback.swift` - Start/stop click sounds
- `Transcriber.swift` - WhisperKit transcription wrapper
- `StreamingTranscriber.swift` - Real-time streaming transcription
- `TextFormatter.swift` - Smart formatting (capitalize, filler removal)
- `TextInserter.swift` - Accessibility API text insertion
- `RustyBarBridge.swift` - IPC to RustyBar (see RUSTYBAR_INTEGRATION.md)
- `HistoryStore.swift` - SwiftData persistence for transcription history
- `ModelManager.swift` - Download and manage Whisper models
- `KeychainManager.swift` - API keys + voice embedding storage
- `Logger.swift` - File + OSLog logging (tail for LLM debugging)
- `VoiceVerifier.swift` - Speaker verification (v0.5)

## Testing

```bash
swift test
```

Tests cover: TextFormatter, HistoryStore, RustyBarBridge, HotkeyManager
