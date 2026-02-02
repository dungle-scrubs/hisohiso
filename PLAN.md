# Hisohiso

A macOS dictation app with local AI transcription, activated by the Globe key.

"Hisohiso" (ひそひそ) means "whisper" in Japanese.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Distribution | Direct (notarized DMG) | No App Store restrictions, Developer ID signing |
| Text display | Streaming | Text appears as you speak, feels instant |
| Cloud support | Optional fallback | Local by default, cloud if user adds API key |
| Recording indicator | Floating pill/badge | Visible feedback near cursor |
| History | Persist locally | Searchable transcription history with timestamps |
| Model management | Download on demand | Smaller initial download, user picks models |
| Default model | Parakeet v2 (English) | Best speed + accuracy for English |
| Pre-commit | SwiftLint + SwiftFormat + swift build | Lint, format, and type check |
| Crash reporting | Sentry | Automatic crash logs in production |
| Dev logging | File tail + Claude Code | Logs to ~/Library/Logs/Hisohiso/ for LLM consumption |
| Recording indicator | RustyBar IPC integration | Real-time state via Unix socket, no floating pill |
| RustyBar fallback | Silent fail | Log warning if RustyBar unavailable, continue normally |
| Auto-launch | Default on | Register as login item during onboarding |
| Menu bar | Minimal | Icon only, click → prefs, right-click → quit |
| Text formatting | Smart (local rules) | Capitalize, punctuation, remove filler words; LLM optional later |
| History retention | Forever | User manually deletes, no auto-cleanup |
| Model storage | ~/Library/Application Support/Hisohiso | Standard macOS location |
| API key storage | macOS Keychain | Secure, survives reinstalls |
| Voice enrollment | Adaptive | Sample until confidence threshold reached |
| Alternative hotkey | Configurable | User can set backup (supports modifier-only too) |
| Audio feedback | Subtle sounds | Quiet click on start/stop |
| Testing | Unit + Integration | XCTest for core logic + IPC/permissions |
| Onboarding | Single checklist | One screen with all setup items and status |
| Audio input | System default | No device selection |
| macOS target | 13 Ventura+ | Wide compatibility, Apple Silicon required |
| Transcription timeout | 10 seconds | Show error state, offer retry |
| History access | RustyBar dropdown | Last 10 with truncated preview, click to copy |
| Error display | RustyBar + floating pill | Normal states in bar, errors show floating pill at bottom |
| Timeout retry | Floating pill with Retry button | Pill appears on error, contains retry action |
| Menu bar icon | Waveform | Audio waveform lines |
| Model download UX | In onboarding | Progress bar in setup checklist |
| Filler words | Editable | User can customize list in preferences |
| Bundle ID | com.{yourname}.hisohiso | Replace {yourname} with your identifier |
| Auto-updates | Sparkle + GitHub Releases | Appcast hosted on GitHub Releases |
| Design philosophy | Minimalist | Clean, unobtrusive, no unnecessary UI chrome |

## Core Features

1. **Globe Key Activation**
   - Hold Globe to record, release to transcribe and insert
   - Tap Globe twice to toggle recording mode
   - Global hotkey works in any app

2. **Local Transcription**
   - WhisperKit for on-device speech-to-text (Whisper + NVIDIA Parakeet models)
   - Default: Parakeet v2 (English) - best speed + accuracy balance
   - Runs on Apple Neural Engine (M1+ required)
   - No data leaves the device

3. **Text Insertion**
   - Inserts transcribed text at cursor position in any app
   - Uses Accessibility API for universal compatibility

4. **Speaker Verification**
   - Enroll your voice once, only transcribe when it's you
   - Ignores other voices (coworkers, TV, background conversations)
   - On-device speaker embedding model

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       Menu Bar App                           │
├──────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────────────┐ │
│  │   Hotkey    │  │   Audio     │  │   Voice Processing    │ │
│  │   Monitor   │─▶│   Capture   │─▶│   (Noise Suppression) │ │
│  │ (CGEventTap)│  │(AVAudioEngine)│  └───────────┬───────────┘ │
│  └─────────────┘  └─────────────┘                │            │
│                                                  ▼            │
│                                    ┌───────────────────────┐ │
│                                    │  Speaker Verification │ │
│                                    │  (ECAPA-TDNN/Silero)  │ │
│                                    └───────────┬───────────┘ │
│                                                │ match?      │
│                                                ▼            │
│                                    ┌───────────────────────┐ │
│                                    │     Transcribe        │ │
│                                    │  (WhisperKit/Parakeet)│ │
│                                    └───────────┬───────────┘ │
│                                                │            │
│  ┌─────────────────────────────────────────────▼───────────┐ │
│  │              Text Insertion (Accessibility)              │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Transcription Models

### Local Models

| Model | Size | Speed | Accuracy | Notes |
|-------|------|-------|----------|-------|
| Tiny | ~66 MB | ●●●●● | ●●○○○ | Fastest, lowest accuracy |
| Base (English) | ~105 MB | ●●●●○ | ●●●○○ | |
| Small (English) | ~330 MB | ●●●○○ | ●●●●○ | |
| Large V3 Turbo | ~954 MB | ●●●●○ | ●●●●● | Good balance |
| Distil Large V3 | ~800 MB | ●●●●● | ●●●●● | Distilled, fast |
| **Parakeet v2 (English)** | ~2.6 GB | ●●●●● | ●●●●● | **Default** - best overall |
| Parakeet v3 (Multilingual) | ~2.7 GB | ●●●●● | ●●●●● | Multi-language support |

**Default:** Parakeet v2 (English) - max speed and accuracy, English-optimized.

### Cloud Providers (Optional)

For users who prefer cloud transcription or need languages not supported locally:

| Provider | Cost | Notes |
|----------|------|-------|
| OpenAI Whisper | ~$0.006/min | High accuracy, requires API key |
| Groq | ~$0.006/min | Faster inference, requires API key |

Cloud providers are optional - the app works fully offline with local models.

## Technical Implementation

### 1. Globe Key Capture

The Globe/Fn key is a modifier key. Capture via `CGEventTap` monitoring `.flagsChanged`:

```swift
import Cocoa

class GlobeKeyMonitor {
    private var eventTap: CFMachPort?
    private var isGlobePressed = false

    var onGlobeDown: (() -> Void)?
    var onGlobeUp: (() -> Void)?

    func start() {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, refcon in
                let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handleFlagsChanged(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let globePressed = flags.contains(.maskSecondaryFn)

        if globePressed && !isGlobePressed {
            isGlobePressed = true
            onGlobeDown?()
        } else if !globePressed && isGlobePressed {
            isGlobePressed = false
            onGlobeUp?()
        }
    }
}
```

**Note:** `.maskSecondaryFn` (value `0x20`) is the flag for the Globe/Fn key.

### 2. Audio Capture

```swift
import AVFoundation

class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []

    func startRecording() {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)
            self?.audioBuffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        try? engine.start()
    }

    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        defer { audioBuffer.removeAll() }
        return audioBuffer
    }
}
```

### 3. Transcription with WhisperKit

```swift
import WhisperKit

class Transcriber {
    private var whisperKit: WhisperKit?

    enum Model: String, CaseIterable {
        case tiny = "tiny"
        case base = "base-en"
        case small = "small-en"
        case largeV3Turbo = "large-v3-turbo"
        case distilLargeV3 = "distil-large-v3"
        case parakeetV2 = "parakeet-v2"          // Default
        case parakeetV3 = "parakeet-v3-multilingual"
    }

    init(model: Model = .parakeetV2) async throws {
        whisperKit = try await WhisperKit(model: model.rawValue)
    }

    func transcribe(_ audioSamples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.notInitialized }

        let results = try await whisperKit.transcribe(audioArray: audioSamples)
        return results.map { $0.text }.joined(separator: " ")
    }
}
```

### 4. Text Insertion

```swift
import Carbon

func insertText(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)

    for char in text {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

        var unicodeChar = Array(String(char).utf16)
        keyDown?.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
        keyUp?.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

Alternative: Use pasteboard + Cmd+V for faster insertion of long text.

### 4b. Streaming Transcription

Process audio in chunks while recording for near-instant text display:

```swift
class StreamingTranscriber {
    private let whisperKit: WhisperKit
    private var audioBuffer: [Float] = []
    private var transcribedText = ""
    private let chunkDuration: TimeInterval = 0.5  // Process every 0.5s

    var onPartialResult: ((String) -> Void)?

    func appendAudio(_ samples: [Float]) async {
        audioBuffer.append(contentsOf: samples)

        // Process when we have enough audio
        let samplesPerChunk = Int(16000 * chunkDuration)  // 16kHz sample rate
        if audioBuffer.count >= samplesPerChunk {
            let chunk = Array(audioBuffer.prefix(samplesPerChunk))

            // Transcribe chunk
            if let result = try? await whisperKit.transcribe(audioArray: chunk) {
                let newText = result.map { $0.text }.joined(separator: " ")
                transcribedText += newText
                onPartialResult?(transcribedText)
            }

            // Keep overlap for context (last 0.1s)
            let overlapSamples = Int(16000 * 0.1)
            audioBuffer = Array(audioBuffer.suffix(overlapSamples))
        }
    }

    func finalize() async -> String {
        // Transcribe any remaining audio
        if !audioBuffer.isEmpty {
            if let result = try? await whisperKit.transcribe(audioArray: audioBuffer) {
                transcribedText += result.map { $0.text }.joined(separator: " ")
            }
        }
        defer {
            audioBuffer.removeAll()
            transcribedText = ""
        }
        return transcribedText.trimmingCharacters(in: .whitespaces)
    }
}
```

**Key points:**
- Process every ~0.5s of audio as it arrives
- Keep small overlap between chunks for context continuity
- Display partial results via `onPartialResult` callback
- Final cleanup when user releases Globe key

### 5. Speaker Verification

Only transcribe audio that matches the enrolled user's voice.

**Voice Embedding Model:** Convert audio → fixed-size vector. Same speaker = similar vectors.

Options:
- **ECAPA-TDNN** - State of the art, convert to CoreML from SpeechBrain
- **Silero Speaker Verification** - Lightweight ONNX model, easy CoreML conversion

```swift
class VoiceVerifier {
    private var enrolledEmbedding: [Float]?
    private let embeddingModel: SpeakerEmbeddingModel  // CoreML model
    private let threshold: Float = 0.75

    // MARK: - Enrollment (run once during setup)

    func enroll(audioSamples: [[Float]]) async {
        // Average multiple embeddings for robustness
        var embeddings: [[Float]] = []
        for sample in audioSamples {
            let embedding = try await embeddingModel.embed(sample)
            embeddings.append(embedding)
        }
        enrolledEmbedding = averageVectors(embeddings)
        saveToKeychain(enrolledEmbedding)
    }

    // MARK: - Verification (run on each recording)

    func verify(audioSamples: [Float]) async -> Bool {
        guard let enrolled = enrolledEmbedding else { return false }

        let currentEmbedding = try await embeddingModel.embed(audioSamples)
        let similarity = cosineSimilarity(enrolled, currentEmbedding)

        return similarity > threshold
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return dot / (normA * normB)
    }

    private func averageVectors(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var result = [Float](repeating: 0, count: first.count)
        for vector in vectors {
            for (i, val) in vector.enumerated() {
                result[i] += val
            }
        }
        return result.map { $0 / Float(vectors.count) }
    }
}
```

**Enrollment Flow:**
1. User speaks 3-5 sample phrases (~10 seconds total)
2. Extract embeddings from each sample
3. Average embeddings and store in Keychain

**Runtime Flow:**
1. Capture first ~1-2 seconds of audio
2. Extract embedding, compare to enrolled
3. If match: continue recording and transcribe
4. If no match: discard audio, show "Voice not recognized"

**Converting Silero to CoreML:**
```bash
pip install onnx coremltools
python -c "
import coremltools as ct
import onnx
model = onnx.load('silero_speaker_v3.onnx')
mlmodel = ct.convert(model)
mlmodel.save('SpeakerEmbedding.mlpackage')
"
```

### 6. RustyBar Integration (Recording Indicator)

Instead of a floating pill, the recording indicator appears in RustyBar via IPC.

**Protocol:** Hisohiso sends state updates to RustyBar's Unix socket at `/tmp/rustybar.sock`.

#### Hisohiso Side (Swift)

```swift
import Foundation

class RustyBarBridge {
    static let shared = RustyBarBridge()
    private let socketPath = "/tmp/rustybar.sock"

    enum HisohisoState: String {
        case idle
        case recording
        case transcribing
        case error
    }

    func setState(_ state: HisohisoState) {
        sendCommand("set hisohiso \(state.rawValue)")
        logDebug("RustyBar state: \(state.rawValue)")
    }

    private func sendCommand(_ command: String) {
        DispatchQueue.global(qos: .utility).async {
            let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socket >= 0 else { return }
            defer { close(socket) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            self.socketPath.withCString { ptr in
                withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                    _ = strcpy(dest, ptr)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connectResult == 0 else {
                logWarning("RustyBar not running or socket unavailable")
                return
            }

            command.withCString { ptr in
                _ = Darwin.write(socket, ptr, strlen(ptr))
            }
        }
    }
}

// Usage in recording flow:
func startRecording() {
    RustyBarBridge.shared.setState(.recording)
    // ... start audio capture
}

func stopRecording() {
    RustyBarBridge.shared.setState(.transcribing)
    // ... transcribe
    RustyBarBridge.shared.setState(.idle)
}
```

#### RustyBar Side (Rust) - Changes Required

**1. New module type in `src/gpui_app/modules/external.rs`:**

```rust
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use gpui::*;
use crate::theme::Theme;
use super::GpuiModule;

// Global state store for external modules
lazy_static::lazy_static! {
    static ref EXTERNAL_STATES: Arc<RwLock<HashMap<String, String>>> =
        Arc::new(RwLock::new(HashMap::new()));
}

pub fn set_external_state(id: &str, state: &str) {
    let mut states = EXTERNAL_STATES.write().unwrap();
    states.insert(id.to_string(), state.to_string());
}

pub fn get_external_state(id: &str) -> Option<String> {
    let states = EXTERNAL_STATES.read().unwrap();
    states.get(id).cloned()
}

pub struct ExternalModule {
    id: String,
    states: HashMap<String, StateConfig>,  // state_name -> display config
    default_state: String,
}

struct StateConfig {
    icon: String,
    color: Option<String>,
    text: Option<String>,
}

impl ExternalModule {
    pub fn new(config: &toml::Value) -> Self {
        let id = config.get("id").and_then(|v| v.as_str()).unwrap_or("external").to_string();

        // Parse state configs from TOML
        let mut states = HashMap::new();
        if let Some(state_table) = config.get("states").and_then(|v| v.as_table()) {
            for (state_name, state_config) in state_table {
                states.insert(state_name.clone(), StateConfig {
                    icon: state_config.get("icon").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                    color: state_config.get("color").and_then(|v| v.as_str()).map(String::from),
                    text: state_config.get("text").and_then(|v| v.as_str()).map(String::from),
                });
            }
        }

        let default_state = config.get("default_state")
            .and_then(|v| v.as_str())
            .unwrap_or("idle")
            .to_string();

        Self { id, states, default_state }
    }

    fn current_state(&self) -> String {
        get_external_state(&self.id).unwrap_or_else(|| self.default_state.clone())
    }
}

impl GpuiModule for ExternalModule {
    fn id(&self) -> &str { &self.id }

    fn render(&self, theme: &Theme) -> AnyElement {
        let state = self.current_state();
        let config = self.states.get(&state);

        let icon = config.map(|c| c.icon.as_str()).unwrap_or("");
        let text = config.and_then(|c| c.text.as_deref()).unwrap_or("");
        let color = config
            .and_then(|c| c.color.as_deref())
            .and_then(|c| parse_color(c))
            .unwrap_or(theme.foreground);

        // Don't render anything if state is idle with no icon
        if state == "idle" && icon.is_empty() && text.is_empty() {
            return div().into_any();
        }

        div()
            .flex()
            .items_center()
            .gap_1()
            .child(div().child(icon).text_color(color))
            .when(!text.is_empty(), |d| d.child(div().child(text).text_color(color)))
            .into_any()
    }

    fn update(&mut self) -> bool {
        true  // Always check for updates since state comes from IPC
    }
}
```

**2. Extend IPC handler in `src/main.rs`:**

```rust
// In the IPC command handler, add:
line if line.starts_with("set ") => {
    let parts: Vec<&str> = line.splitn(3, ' ').collect();
    if parts.len() >= 3 {
        let module_id = parts[1];
        let state = parts[2].trim();
        external::set_external_state(module_id, state);
        cx.refresh();  // Trigger redraw
    }
    "OK"
}
```

**3. Register in module factory (`src/gpui_app/modules/mod.rs`):**

```rust
"external" => Box::new(external::ExternalModule::new(config)),
```

#### RustyBar Config

```toml
[[modules.right.left]]
type = "external"
id = "hisohiso"
default_state = "idle"

[modules.right.left.states.idle]
icon = ""
# Empty = hidden when idle

[modules.right.left.states.recording]
icon = "●"
color = "#ff5555"
text = ""

[modules.right.left.states.transcribing]
icon = "◐"
color = "#f1fa8c"
text = ""

[modules.right.left.states.error]
icon = "✗"
color = "#ff5555"
text = ""
```

#### States

| State | Icon | Color | Meaning |
|-------|------|-------|---------|
| `idle` | (hidden) | - | Not recording |
| `recording` | ● | Red | Actively recording |
| `transcribing` | ◐ | Yellow | Processing audio |
| `error` | ✗ | Red | Transcription failed |

#### History Popup in RustyBar

The Hisohiso module can show a dropdown with recent transcriptions:

**RustyBar config with popup:**
```toml
[[modules.right.left]]
type = "external"
id = "hisohiso"
default_state = "idle"
popup = true
popup_width = 300
popup_height = 400
popup_command = "/Applications/Hisohiso.app/Contents/MacOS/Hisohiso --history-json"

# ... states config ...
```

**Hisohiso CLI for history:**
```swift
// --history-json returns last 10 transcriptions as JSON
if CommandLine.arguments.contains("--history-json") {
    let history = HistoryStore.shared.recent(limit: 10)
    let json = history.map { record in
        [
            "id": record.id.uuidString,
            "text": String(record.text.prefix(100)),  // Truncated preview
            "timestamp": ISO8601DateFormatter().string(from: record.timestamp)
        ]
    }
    print(try! JSONSerialization.data(withJSONObject: json).string)
    exit(0)
}
```

**Popup behavior:**
- Click module → show dropdown with last 10 transcriptions
- Each item shows truncated text + relative timestamp
- Click item → copy full text to clipboard
- RustyBar needs popup rendering support for external modules (future enhancement)
```

### 7. Smart Text Formatting

Local rules-based formatting applied after transcription:

```swift
class TextFormatter {
    // Filler words to remove
    private let fillerWords = [
        "um", "uh", "er", "ah",
        "like", "you know", "basically", "actually",
        "i mean", "sort of", "kind of"
    ]

    func format(_ text: String) -> String {
        var result = text

        // 1. Remove filler words (case-insensitive, word boundaries)
        for filler in fillerWords {
            let pattern = "\\b\(filler)\\b,?\\s*"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 2. Fix multiple spaces
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)

        // 3. Capitalize after sentence-ending punctuation
        result = result.replacingOccurrences(
            of: "([.!?])\\s+([a-z])",
            with: "$1 $2",
            options: .regularExpression
        ).capitalizingFirstLetterAfterPunctuation()

        // 4. Capitalize first letter
        result = result.trimmingCharacters(in: .whitespaces)
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        // 5. Ensure ending punctuation
        if let last = result.last, !last.isPunctuation {
            result += "."
        }

        return result
    }
}

extension String {
    func capitalizingFirstLetterAfterPunctuation() -> String {
        var result = ""
        var capitalizeNext = false

        for char in self {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "!" || char == "?" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }
}
```

**Future enhancement:** Optional LLM-based formatting (local llama.cpp or cloud API) for grammar correction and more natural phrasing.

### 8. History Store

Persist transcriptions locally using SwiftData:

```swift
import SwiftData

@Model
class TranscriptionRecord {
    var id: UUID
    var text: String
    var timestamp: Date
    var duration: TimeInterval
    var model: String

    init(text: String, duration: TimeInterval, model: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.model = model
    }
}

class HistoryStore {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(for: TranscriptionRecord.self)
    }

    @MainActor
    func save(_ text: String, duration: TimeInterval, model: String) throws {
        let record = TranscriptionRecord(text: text, duration: duration, model: model)
        container.mainContext.insert(record)
        try container.mainContext.save()
    }

    @MainActor
    func search(_ query: String) throws -> [TranscriptionRecord] {
        let predicate = #Predicate<TranscriptionRecord> { record in
            record.text.localizedStandardContains(query)
        }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try container.mainContext.fetch(descriptor)
    }
}
```

### 8. Logging & Crash Reporting

**Development:** Logs to file for Claude Code consumption via `tail -f`.

**Production:** Sentry for automatic crash reporting.

```swift
import OSLog
import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

class Logger {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.hisohiso.app", category: "general")
    private let fileHandle: FileHandle?
    private let logFileURL: URL

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    private init() {
        // Create log directory
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hisohiso")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create/open log file (rotates daily)
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        logFileURL = logsDir.appendingPathComponent("hisohiso-\(dateStr).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"

        // Write to OSLog
        os_log("%{public}@", log: osLog, type: level.osLogType, message)

        // Write to file (for Claude Code tail)
        #if DEBUG
        if let data = logLine.data(using: .utf8) {
            fileHandle?.write(data)
            fileHandle?.synchronizeFile()
        }
        #endif
    }

    var logFilePath: String { logFileURL.path }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

// Convenience functions
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .debug, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .info, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .warning, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, level: .error, file: file, function: function, line: line)
}
```

**Usage during development:**
```bash
# In a separate terminal, tail logs for Claude Code to consume
tail -f ~/Library/Logs/Hisohiso/hisohiso-*.log
```

Then ask Claude Code: "Check the log output and help me debug this issue"

**Sentry Setup (Production):**

```swift
import Sentry

@main
struct HisohisoApp: App {
    init() {
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = "https://your-sentry-dsn"
            options.tracesSampleRate = 0.2
            options.attachStacktrace = true
            options.enableAutoSessionTracking = true
        }
        #endif
    }

    var body: some Scene {
        // ...
    }
}
```

Add to Package.swift:
```swift
.package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),
```

### 10. Configurable Hotkey

Support both Globe key and a user-configurable alternative:

```swift
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var globeMonitor: GlobeKeyMonitor?
    private var alternativeHotkey: HotKey?

    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    // Alternative hotkey stored in UserDefaults
    @AppStorage("alternativeHotkey") var alternativeHotkeyData: Data?

    func start() {
        // Always monitor Globe key
        globeMonitor = GlobeKeyMonitor()
        globeMonitor?.onGlobeDown = { [weak self] in self?.onActivate?() }
        globeMonitor?.onGlobeUp = { [weak self] in self?.onDeactivate?() }
        globeMonitor?.start()

        // Register alternative if configured
        if let data = alternativeHotkeyData,
           let keyCombo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            registerAlternative(keyCombo)
        }
    }

    func setAlternativeHotkey(_ keyCombo: KeyCombo?) {
        alternativeHotkey?.unregister()

        if let keyCombo {
            alternativeHotkeyData = try? JSONEncoder().encode(keyCombo)
            registerAlternative(keyCombo)
        } else {
            alternativeHotkeyData = nil
        }
    }

    private func registerAlternative(_ keyCombo: KeyCombo) {
        // Support both standard (Cmd+Shift+Space) and modifier-only (double-tap Shift)
        if keyCombo.isModifierOnly {
            // Use CGEventTap for modifier-only detection
            setupModifierOnlyHotkey(keyCombo)
        } else {
            // Use Carbon RegisterEventHotKey for standard shortcuts
            alternativeHotkey = HotKey(keyCombo: keyCombo)
            alternativeHotkey?.keyDownHandler = { [weak self] in self?.onActivate?() }
            alternativeHotkey?.keyUpHandler = { [weak self] in self?.onDeactivate?() }
        }
    }
}

struct KeyCombo: Codable {
    var keyCode: UInt32?           // nil for modifier-only
    var modifiers: CGEventFlags
    var isModifierOnly: Bool
    var doubleTap: Bool            // For double-tap detection

    static let cmdShiftSpace = KeyCombo(keyCode: 49, modifiers: [.maskCommand, .maskShift], isModifierOnly: false, doubleTap: false)
    static let doubleTapShift = KeyCombo(keyCode: nil, modifiers: .maskShift, isModifierOnly: true, doubleTap: true)
}
```

### 11. Audio Feedback

Subtle click sounds on recording start/stop:

```swift
import AVFoundation

class AudioFeedback {
    static let shared = AudioFeedback()

    private var startSound: AVAudioPlayer?
    private var stopSound: AVAudioPlayer?

    @AppStorage("audioFeedbackEnabled") var isEnabled = true

    init() {
        if let startURL = Bundle.main.url(forResource: "start", withExtension: "wav"),
           let stopURL = Bundle.main.url(forResource: "stop", withExtension: "wav") {
            startSound = try? AVAudioPlayer(contentsOf: startURL)
            stopSound = try? AVAudioPlayer(contentsOf: stopURL)
            startSound?.prepareToPlay()
            stopSound?.prepareToPlay()
        }
    }

    func playStart() {
        guard isEnabled else { return }
        startSound?.currentTime = 0
        startSound?.play()
    }

    func playStop() {
        guard isEnabled else { return }
        stopSound?.currentTime = 0
        stopSound?.play()
    }
}
```

Sound files: Short, subtle clicks (~50ms). Can use system sounds or bundle custom WAVs.

### 12. Floating Pill Indicator

A floating pill at the bottom of the screen showing recording state. Used as primary indicator until RustyBar integration (v0.4).

```swift
enum RecordingState {
    case idle
    case recording
    case transcribing
    case error(message: String, onRetry: () -> Void)
}

class FloatingPillWindow: NSWindow {
    private var hostingView: NSHostingView<FloatingPillView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    func show(state: RecordingState) {
        if case .idle = state {
            orderOut(nil)
            return
        }

        contentView = NSHostingView(rootView: FloatingPillView(
            state: state,
            onDismiss: { [weak self] in self?.orderOut(nil) }
        ))

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - frame.width) / 2
            let y: CGFloat = 80  // Above dock
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFront(nil)
    }
}

struct FloatingPillView: View {
    let state: RecordingState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text("Recording...")

            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Transcribing...")

            case .error(let message, let onRetry):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .lineLimit(1)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.black.opacity(0.85)))
    }
}
```

**States:**
| State | Display |
|-------|---------|
| `idle` | Hidden |
| `recording` | Red dot + "Recording..." |
| `transcribing` | Spinner + "Transcribing..." |
| `error` | Warning icon + message + Retry button |

**Behavior:**
- Appears on recording start, hides when idle
- Error state shows retry button
- Auto-dismiss errors after 10 seconds if no action
- Design TBD - this is a starting point

### 13. Onboarding Checklist

Single-screen setup showing all required items with live status:

```swift
struct OnboardingView: View {
    @State private var micPermission = false
    @State private var accessibilityPermission = false
    @State private var inputMonitoringPermission = false
    @State private var globeKeyDisabled = false
    @State private var modelDownloaded = false
    @State private var loginItemEnabled = false

    var allComplete: Bool {
        micPermission && accessibilityPermission && inputMonitoringPermission &&
        globeKeyDisabled && modelDownloaded && loginItemEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup Hisohiso")
                .font(.title)

            ChecklistItem(
                title: "Microphone Access",
                status: micPermission,
                action: requestMicPermission
            )

            ChecklistItem(
                title: "Accessibility Permission",
                subtitle: "For global hotkey and text insertion",
                status: accessibilityPermission,
                action: openAccessibilityPrefs
            )

            ChecklistItem(
                title: "Input Monitoring",
                subtitle: "For keyboard event capture",
                status: inputMonitoringPermission,
                action: openInputMonitoringPrefs
            )

            ChecklistItem(
                title: "Disable Globe Key Dictation",
                subtitle: "System Settings → Keyboard → Press 🌐 to → Do Nothing",
                status: globeKeyDisabled,
                action: openKeyboardPrefs
            )

            ChecklistItem(
                title: "Download Parakeet v2 Model",
                subtitle: "~2.6 GB, required for transcription",
                status: modelDownloaded,
                action: downloadModel
            )

            ChecklistItem(
                title: "Launch at Login",
                status: loginItemEnabled,
                action: enableLoginItem
            )

            Spacer()

            Button("Get Started") {
                closeOnboarding()
            }
            .disabled(!allComplete)
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 450, height: 500)
        .onAppear { refreshStatuses() }
    }
}

struct ChecklistItem: View {
    let title: String
    var subtitle: String? = nil
    let status: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: status ? "checkmark.circle.fill" : "circle")
                .foregroundColor(status ? .green : .secondary)

            VStack(alignment: .leading) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !status {
                Button("Setup", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}
```

## Required Permissions

| Permission | Purpose | How to Request |
|------------|---------|----------------|
| Microphone | Audio capture | `AVCaptureDevice.requestAccess(for: .audio)` |
| Accessibility | Global hotkey, text insertion | System Settings prompt (manual) |
| Input Monitoring | Keyboard event monitoring | `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` |

## User Onboarding

Users must disable the system Globe key binding:

1. Open **System Settings → Keyboard**
2. Find **"Press 🌐 key to"**
3. Change from "Start Dictation" to **"Do Nothing"**

Consider adding an onboarding screen that detects this setting and guides users.

## Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),
]
```

**Additional for v0.4 (Speaker Verification):**
- `SpeakerEmbedding.mlpackage` - CoreML model converted from Silero or ECAPA-TDNN
- Security framework for Keychain storage of voice embedding

## Pre-commit Hooks

Using SwiftLint for linting, SwiftFormat for formatting, and `swift build` for type checking.

### Setup

```bash
# Install tools
brew install swiftlint swiftformat pre-commit

# Initialize pre-commit
pre-commit install
```

### .pre-commit-config.yaml

```yaml
repos:
  - repo: local
    hooks:
      - id: swiftformat
        name: SwiftFormat
        entry: swiftformat --config .swiftformat
        language: system
        files: \.swift$

      - id: swiftlint
        name: SwiftLint
        entry: swiftlint --strict --config .swiftlint.yml
        language: system
        files: \.swift$

      - id: swift-build
        name: Type Check (swift build)
        entry: swift build
        language: system
        pass_filenames: false
        always_run: true
```

### .swiftlint.yml

```yaml
disabled_rules:
  - trailing_whitespace
  - line_length

opt_in_rules:
  - empty_count
  - explicit_init
  - closure_spacing
  - overridden_super_call
  - redundant_nil_coalescing
  - private_outlet
  - nimble_operator
  - attributes
  - closure_end_indentation
  - first_where
  - prohibited_super_call
  - fatal_error_message

excluded:
  - .build
  - Package.swift
```

### .swiftformat

```
--swiftversion 5.9
--indent 4
--indentcase false
--trimwhitespace always
--voidtype void
--nospaceoperators ..<, ...
--ifdef noindent
--stripunusedargs closure-only
--maxwidth 120
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
```

## Project Structure

```
hisohiso/
├── Package.swift
├── .pre-commit-config.yaml
├── .swiftlint.yml
├── .swiftformat
├── Makefile                              # Common tasks (build, lint, format)
├── RUSTYBAR_INTEGRATION.md               # RustyBar changes documentation
├── Sources/
│   └── Hisohiso/
│       ├── App.swift                     # @main, menu bar setup, login item
│       ├── GlobeKeyMonitor.swift         # CGEventTap for Globe key
│       ├── HotkeyManager.swift           # Globe + configurable alternative hotkey
│       ├── AudioRecorder.swift           # AVAudioEngine capture
│       ├── AudioFeedback.swift           # Start/stop click sounds
│       ├── Transcriber.swift             # WhisperKit wrapper
│       ├── StreamingTranscriber.swift    # Real-time streaming transcription
│       ├── TextFormatter.swift           # Smart formatting (capitalize, filler removal)
│       ├── TextInserter.swift            # Accessibility text insertion
│       ├── RecordingState.swift          # State machine for recording
│       ├── ModelManager.swift            # Download/manage Whisper models
│       ├── HistoryStore.swift            # SwiftData persistence
│       ├── Logger.swift                  # File + OSLog logging for LLM consumption
│       ├── KeychainManager.swift         # API keys + voice embedding storage
│       ├── RustyBarBridge.swift          # IPC to RustyBar
│       ├── VoiceVerifier.swift           # Speaker verification (v0.5)
│       ├── CloudProviders/
│       │   ├── CloudProvider.swift       # Protocol
│       │   ├── OpenAIProvider.swift
│       │   └── GroqProvider.swift
│       ├── UI/
│       │   ├── OnboardingView.swift      # Single checklist setup screen
│       │   ├── FloatingPillWindow.swift  # Recording/error indicator
│       │   └── HistoryView.swift
│       └── Preferences/
│           ├── PreferencesView.swift
│           ├── GeneralTab.swift          # Audio feedback, launch at login
│           ├── HotkeyTab.swift           # Globe + alternative hotkey config
│           ├── ModelsTab.swift           # Model selection + download
│           ├── FormattingTab.swift       # Filler words, LLM option
│           ├── CloudTab.swift            # API keys
│           └── VoiceEnrollmentTab.swift  # Speaker verification (v0.5)
├── Tests/
│   └── HisohisoTests/
│       ├── TextFormatterTests.swift
│       ├── HistoryStoreTests.swift
│       ├── RustyBarBridgeTests.swift
│       └── HotkeyManagerTests.swift
└── Resources/
    ├── Assets.xcassets
    ├── start.wav                         # Recording start sound
    ├── stop.wav                          # Recording stop sound
    └── SpeakerEmbedding.mlpackage        # CoreML speaker model (v0.5)
```

## MVP Milestones

### v0.1 - Core (Pill + Globe Key + Parakeet v2)
- [ ] Project setup (Package.swift, pre-commit hooks, macOS 13+ target)
- [ ] Logger setup (file + OSLog for Claude Code tail)
- [ ] Globe key detection (hold to record, release to transcribe)
- [ ] Floating pill indicator (recording state, bottom of screen)
- [ ] Audio capture with noise suppression (system default input)
- [ ] WhisperKit transcription with Parakeet v2
- [ ] Model download + storage in ~/Library/Application Support/Hisohiso
- [ ] Text insertion at cursor
- [ ] Basic error handling (error pill with retry button)

### v0.2 - Streaming & Polish
- [ ] Streaming transcription (text appears as you speak)
- [ ] Smart text formatting (capitalize, punctuation, remove filler words)
- [ ] Double-tap toggle mode
- [ ] Menu bar app shell (minimal: icon only, click→prefs, right-click→quit)
- [ ] 10-second transcription timeout with error state
- [ ] Audio feedback (subtle click on start/stop)
- [ ] Onboarding checklist (single screen with all setup items)
- [ ] Launch at login (default on)

### v0.3 - History & Hotkeys
- [ ] Transcription history (SwiftData, kept forever)
- [ ] History view (searchable, click to copy)
- [ ] Configurable alternative hotkey (standard + modifier-only support)
- [ ] Preferences window (model, hotkey, audio feedback, formatting)
- [ ] Editable filler word list
- [ ] API key storage in macOS Keychain
- [ ] Unit + Integration tests (XCTest)

### v0.4 - RustyBar Integration
- [ ] RustyBar IPC integration (RustyBarBridge)
- [ ] RustyBar external module (Rust side - see ~/dev/rustybar)
- [ ] RustyBar history popup (last 10, truncated preview, click to copy)
- [ ] Hisohiso --history-json CLI for RustyBar
- [ ] Option to hide floating pill when RustyBar active

### v0.5 - Cloud & Models
- [ ] Cloud providers (OpenAI, Groq) as optional fallback
- [ ] Multiple model support in preferences
- [ ] LLM-based formatting option (local llama.cpp or cloud)

### v0.6 - Speaker Verification
- [ ] Convert Silero/ECAPA-TDNN to CoreML
- [ ] Adaptive voice enrollment (sample until confidence threshold)
- [ ] Store voice embedding in Keychain
- [ ] Verify speaker before transcription
- [ ] "Voice not recognized" feedback
- [ ] Re-enrollment option in preferences
- [ ] Confidence/sensitivity slider

### v0.7 - Distribution
- [ ] Sentry crash reporting (production only)
- [ ] App icon and branding
- [ ] Developer ID signing
- [ ] Notarization
- [ ] DMG packaging with install instructions
- [ ] Auto-update mechanism (Sparkle)

## Resources

**Transcription:**
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [NVIDIA Parakeet Models](https://huggingface.co/nvidia/parakeet-tdt-1.1b)
- [WhisperKit Model Repository](https://huggingface.co/argmaxinc/whisperkit-coreml)

**Globe Key Capture:**
- [CGEventTap Documentation](https://developer.apple.com/documentation/coregraphics/cgeventtapcreate(_:_:_:_:_:_:))
- [fn key detection in Swift](https://blog.rampatra.com/how-to-detect-fn-key-press-in-swift)
- [macOS keyboard event interception](https://www.logcg.com/en/archives/2902.html)
- [pqrs-org event observer examples](https://github.com/pqrs-org/osx-event-observer-examples)

**Speaker Verification:**
- [Silero Models (includes speaker verification)](https://github.com/snakers4/silero-models)
- [SpeechBrain ECAPA-TDNN](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb)
- [CoreML Tools - ONNX conversion](https://apple.github.io/coremltools/docs-guides/source/convert-onnx.html)
- [Resemblyzer (Python reference)](https://github.com/resemble-ai/Resemblyzer)

**RustyBar Integration:**
- See [RUSTYBAR_INTEGRATION.md](./RUSTYBAR_INTEGRATION.md) for Rust-side changes
- RustyBar repo: ~/dev/rustybar
