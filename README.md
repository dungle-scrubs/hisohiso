# Hisohiso

Local-first macOS dictation app with multi-backend transcription, activated by
Globe key.

Hisohiso (ひそひそ — Japanese for "whisper") runs entirely on-device using
Apple Silicon's Neural Engine. Press the Globe key, speak, and your words
appear at the cursor. No cloud required.

## Features

- **Globe key activation** — tap to dictate, hold for continuous recording
- **Multi-backend transcription** — Parakeet v2 (best English accuracy) and
  Whisper (100+ languages) via CoreML
- **Smart formatting** — auto-capitalization, punctuation, filler word removal
- **Text insertion** — transcribed text inserted directly at cursor position
- **Wake word** — optional always-listening trigger phrase
- **History** — searchable transcription history with quick-paste
- **Cloud fallback** — optional OpenAI/Groq API for when local isn't enough
- **Sinew integration** — native waveform module for external status display
- **Minimal UI** — menu bar icon, floating pill indicator, nothing else

## Requirements

- **macOS 14 Sonoma** or later
- **Apple Silicon** (M1+) for Neural Engine acceleration
- ~2.6 GB disk space for Parakeet v2 model (downloaded on first run)

### Permissions

Hisohiso requests these permissions on first launch:

| Permission | Why |
|------------|-----|
| Accessibility | Capture Globe key globally, insert text at cursor |
| Input Monitoring | Keyboard event detection |
| Microphone | Audio recording for transcription |

## Installation

### Homebrew

```bash
brew install dungle-scrubs/hisohiso/hisohiso
```

Then run `hisohiso` to launch.

### Download

Grab the latest `.tar.gz` from
[GitHub Releases](https://github.com/dungle-scrubs/hisohiso/releases).

### Build from source

```bash
git clone https://github.com/dungle-scrubs/hisohiso.git
cd hisohiso
swift build -c release
```

Or open in Xcode:

```bash
open Package.swift
```

## Usage

1. Launch Hisohiso — a waveform icon appears in the menu bar
2. Complete the onboarding checklist (permissions + model download)
3. Press the **Globe key** (🌐) to start dictating
4. Speak — release the key or tap again to stop
5. Transcribed text appears at your cursor

> **Tip:** Set Globe key to "Do Nothing" in System Settings → Keyboard to
> prevent conflicts.

### Transcription models

| Model | Backend | Languages | Accuracy | Size |
|-------|---------|-----------|----------|------|
| **Parakeet v2** ⭐ | FluidAudio | English | 1.69% WER | 2.6 GB |
| Parakeet v3 | FluidAudio | 25 EU langs | ~2% WER | 2.7 GB |
| Whisper Large V3 Turbo | WhisperKit | 100+ langs | ~2.5% WER | 954 MB |
| Whisper Distil Large V3 | WhisperKit | 100+ langs | ~3% WER | 800 MB |
| Whisper Small English | WhisperKit | English | ~4% WER | 330 MB |

Switch models from the menu bar right-click menu or Preferences.

### History

Press **⌃⌥Space** to open the history palette. Select an entry to insert it
at your cursor (or copy to clipboard).

### Cloud providers

Optional. Add API keys in Preferences → Cloud for OpenAI or Groq transcription
as a fallback. Keys are stored in the macOS Keychain.

## Configuration

Click the menu bar icon to open Preferences:

- **General** — auto-launch, audio feedback, formatting options
- **Hotkey** — alternative hotkey (modifier-only supported)
- **Model** — select transcription model, manage downloads
- **Cloud** — API keys for OpenAI/Groq
- **Voice** — speaker verification enrollment
- **Wake Word** — configure always-listening trigger phrase

## Development

### Prerequisites

```bash
brew install swiftlint swiftformat pre-commit trufflehog
```

### Setup

```bash
make setup    # Installs pre-commit hooks
make build    # Build debug
make test     # Run tests (127 tests)
make lint     # SwiftLint
make format   # SwiftFormat
```

### Logging

Logs write to `~/Library/Logs/Hisohiso/`:

```bash
make logs     # tail -f the latest log
```

### Pre-commit hooks

Runs automatically on commit: SwiftFormat → SwiftLint → `swift build`.
TruffleHog secret scanning runs on push.

## Architecture

| File | Responsibility |
|------|---------------|
| `App.swift` | Entry point, menu bar, app delegate |
| `DictationController.swift` | Orchestrates record → transcribe → insert |
| `GlobeKeyMonitor.swift` | CGEventTap for Globe/Fn key detection |
| `HotkeyManager.swift` | Configurable alternative hotkey |
| `AudioRecorder.swift` | AVAudioEngine audio capture |
| `Transcriber.swift` | Multi-backend transcription (FluidAudio + WhisperKit) |
| `ModelManager.swift` | Download and manage transcription models |
| `TextFormatter.swift` | Smart formatting (capitalize, filler removal) |
| `TextInserter.swift` | Accessibility API text insertion |
| `SinewBridge.swift` | IPC to Sinew for external UI |
| `HistoryStore.swift` | SwiftData persistence |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

[MIT](LICENSE) © Kevin Frilot
