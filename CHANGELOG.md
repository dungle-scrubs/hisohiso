# Changelog

## [0.2.0](https://github.com/dungle-scrubs/hisohiso/compare/v0.1.0...v0.2.0) (2026-02-24)


### ⚠ BREAKING CHANGES

* public release ([#9](https://github.com/dungle-scrubs/hisohiso/issues/9))
* rename RustyBar to Sinew

### Added

* add Homebrew formula and release build pipeline ([#12](https://github.com/dungle-scrubs/hisohiso/issues/12)) ([8d0742e](https://github.com/dungle-scrubs/hisohiso/commit/8d0742e85688e0c32417a6aa9a0a1ab787e415e5))
* Add launch at login and onboarding (window display WIP) ([e222905](https://github.com/dungle-scrubs/hisohiso/commit/e222905718fc36ba883e47d1614d61809a87cd68))
* Add Preferences window (v0.3) ([b0316ce](https://github.com/dungle-scrubs/hisohiso/commit/b0316ce8a9c8540e4704e87e989e4d17b79209e5))
* Add StreamingTranscriber for future real-time transcription ([2d28056](https://github.com/dungle-scrubs/hisohiso/commit/2d280562fd6e8a47994823d8978c226ce1c9f352))
* **app:** add microphone menu and separate indicator toggles ([5ed37fb](https://github.com/dungle-scrubs/hisohiso/commit/5ed37fb7ba22ff34d19db4c752bbfd4179b54b57))
* **app:** integrate wake word detection into app lifecycle ([d197e86](https://github.com/dungle-scrubs/hisohiso/commit/d197e86c36b30741585419b68f3abb4edf605561))
* **audio:** add AudioKit recorder for noise suppression ([23cc586](https://github.com/dungle-scrubs/hisohiso/commit/23cc5867e59c31f52eb8cfc9de45f9c3fa60a40f))
* **audio:** add monitoring mode for continuous wake word listening ([e83fb62](https://github.com/dungle-scrubs/hisohiso/commit/e83fb6202015f7dde043900281b328a911e43c44))
* **cloud:** add cloud transcription providers (OpenAI, Groq) ([82524f8](https://github.com/dungle-scrubs/hisohiso/commit/82524f832985f3a8800bbb45528183611ed2b8c7))
* **dictation:** add auto-stop on silence for wake word recordings ([24e2d0f](https://github.com/dungle-scrubs/hisohiso/commit/24e2d0f13dcfeabde5f89a77ab0cccd5c50e83cb))
* Dual input modes - tap toggle and hold-to-record ([4646b87](https://github.com/dungle-scrubs/hisohiso/commit/4646b87ad8f5c16c2ec0116680db3cd7f201a158))
* **history:** add click-outside-to-dismiss and hover-to-select ([2cdb41c](https://github.com/dungle-scrubs/hisohiso/commit/2cdb41cb25295c71a57a04e486fd2d449ca3b160))
* **history:** add Spotlight-style history palette ([949152b](https://github.com/dungle-scrubs/hisohiso/commit/949152b5b4430f9dc91464841da5a3babc5ee3ee))
* **history:** integrate history saving and palette hotkey ([ceb7a65](https://github.com/dungle-scrubs/hisohiso/commit/ceb7a65523c472d8538dc3d698ec7eb2634e4f36))
* **hotkey:** add configurable alternative dictation hotkey ([386c264](https://github.com/dungle-scrubs/hisohiso/commit/386c264248ef66beec0f0afa848758426f3a6317))
* **integration:** migrate to Sinew and secure IO paths ([3f9f2b2](https://github.com/dungle-scrubs/hisohiso/commit/3f9f2b225943499d1be3291ea1f393eac415d377))
* **keychain:** add KeychainManager for secure API key storage ([b9d26d8](https://github.com/dungle-scrubs/hisohiso/commit/b9d26d86b92ad78e2b691f3a6a35d3d2fff781a7))
* **pill:** add animated waveform matching RustyBar style ([46041a7](https://github.com/dungle-scrubs/hisohiso/commit/46041a77378ad776c9d11905f8025beaacdadf0e))
* **pill:** add auto-dismiss and click-to-dismiss for error state ([83b7f80](https://github.com/dungle-scrubs/hisohiso/commit/83b7f8051789a26d7f19a66620d059faa118958e))
* **prefs:** add microphone selection and AudioKit toggle ([0fa0129](https://github.com/dungle-scrubs/hisohiso/commit/0fa0129f1b24e376c15b001bb060050f06fe928a))
* **prefs:** add Wake Word preferences tab ([a20920b](https://github.com/dungle-scrubs/hisohiso/commit/a20920b7e2a8914430bf97916d1db0f1b1e6c6f7))
* public release ([#9](https://github.com/dungle-scrubs/hisohiso/issues/9)) ([8510a61](https://github.com/dungle-scrubs/hisohiso/commit/8510a616489ad92e914f7812e0de81a588b148bc))
* **recording:** add escape key to cancel recording ([3cfcb07](https://github.com/dungle-scrubs/hisohiso/commit/3cfcb0726aa29d8b53ef9a44a29fc7ad38a23b00))
* **rustybar:** add RustyBar IPC bridge for status bar integration ([93f9a65](https://github.com/dungle-scrubs/hisohiso/commit/93f9a6502256641d2c6790c46acefcb43cc05745))
* **sinew:** native waveform module with persistent IPC ([#8](https://github.com/dungle-scrubs/hisohiso/issues/8)) ([dc12033](https://github.com/dungle-scrubs/hisohiso/commit/dc12033803f89dfcf94548ff411247a7b9623877))
* **transcriber:** add Parakeet v2 support and warmup ([011bfdf](https://github.com/dungle-scrubs/hisohiso/commit/011bfdfd9dac5fdc188bf2ae5ddc059606294da8))
* **transcription:** add Parakeet v2 support via FluidAudio ([112d27c](https://github.com/dungle-scrubs/hisohiso/commit/112d27c7083a8fa7d2175fafdd1e399e2b94f3a4))
* v0.1 - Core dictation flow working ([557ebd3](https://github.com/dungle-scrubs/hisohiso/commit/557ebd3ff12a4961bc58a4a1ff67a38766595e27))
* v0.2 - Text formatting and audio feedback ([67410e5](https://github.com/dungle-scrubs/hisohiso/commit/67410e57fa9104eeaac74dc435446a3ff73e8019))
* **voice:** add VoiceVerifier for speaker verification ([ce965d5](https://github.com/dungle-scrubs/hisohiso/commit/ce965d5ab296f3dcd63f115bd3764d55735f2b44))
* **wake-word:** add WakeWordManager with VAD + Whisper tiny ([2000697](https://github.com/dungle-scrubs/hisohiso/commit/2000697f39b3ce981dc8bf793c0909be032cf734))


### Fixed

* **audio:** improve resampling with vDSP and add normalization ([ada0a47](https://github.com/dungle-scrubs/hisohiso/commit/ada0a4754aad8feca7241c572f7e1b43cbaeb151))
* **core:** isolate history tests and tap ownership ([0551567](https://github.com/dungle-scrubs/hisohiso/commit/0551567bd4ea82d8e3fb86363dc8f177c606fb79))
* **dictation:** handle short audio gracefully and fix hold-to-stop ([744b390](https://github.com/dungle-scrubs/hisohiso/commit/744b3906099152b5f60a3fda1865ccaf9194eacc))
* **formatter:** use word boundaries to prevent partial filler matches ([bf126e4](https://github.com/dungle-scrubs/hisohiso/commit/bf126e4b067c2bf4ddfb0f6d3f477e8f885ce61e))
* **login:** prevent terminal startup launch ([#4](https://github.com/dungle-scrubs/hisohiso/issues/4)) ([d61e20f](https://github.com/dungle-scrubs/hisohiso/commit/d61e20fc7d4d3f7cd01f7753ed85bd56b19ec9eb))
* Onboarding window now appears correctly ([eda7282](https://github.com/dungle-scrubs/hisohiso/commit/eda728222d15493a3ed9f90d9c753a6414013882))
* resolve concurrency, state machine, and correctness issues ([3f050e1](https://github.com/dungle-scrubs/hisohiso/commit/3f050e1906faf93eaad88d7da9d5267851b915a2))
* **sinew:** replace strcpy with bounds-checked copy ([2436856](https://github.com/dungle-scrubs/hisohiso/commit/2436856d37d0cf52f3d122d3f7aefd65017200a1))
* thread safety for Logger, AudioRecorder, VoiceVerifier, WakeWordManager ([9932470](https://github.com/dungle-scrubs/hisohiso/commit/9932470e89d3b487b649065c4ca8fb31cdc25b39))
* **transcription:** harden downloads and fallback errors ([4632a36](https://github.com/dungle-scrubs/hisohiso/commit/4632a3668ed9d20ef2694d5801bf263a908ecdcb))
* **ui:** FloatingPill lifecycle, toast retention, prod menu ([56e8420](https://github.com/dungle-scrubs/hisohiso/commit/56e8420ac2051c66c75e4ddc76e63b60a1dd9932))


### Changed

* extract AudioDSP, reduce filler aggressiveness ([622dd46](https://github.com/dungle-scrubs/hisohiso/commit/622dd4602978b2e8036a71a883a99e7ef58cdbcf))
* remove dead code and fix compiler warnings ([1dea312](https://github.com/dungle-scrubs/hisohiso/commit/1dea3121c7e2a8c6e34553f625f0beb82b280517))
* rename RustyBar to Sinew ([72ecd5c](https://github.com/dungle-scrubs/hisohiso/commit/72ecd5c7966011670d2b17765867aa92a4cbe03c))
* split PreferencesWindow into tab views ([f585907](https://github.com/dungle-scrubs/hisohiso/commit/f585907849ff05f1e997205ccbc0cef7cf168623))
* Warmup transcriber on startup for instant first transcription ([0c05fc1](https://github.com/dungle-scrubs/hisohiso/commit/0c05fc168d4c7b82541daa823a66f62d9ea75cbd))


### Documentation

* add JSDoc to public APIs ([b416d38](https://github.com/dungle-scrubs/hisohiso/commit/b416d3878176660fe8b6c1bfdf9d406e2a8fa4ca))
* Add lessons learned to CLAUDE.md ([57ff481](https://github.com/dungle-scrubs/hisohiso/commit/57ff4811e6141e01a5e17c211a9329a9b4a5e5df))
* update CLAUDE.md for Parakeet and macOS 14 ([1deadd6](https://github.com/dungle-scrubs/hisohiso/commit/1deadd6175eb42065a053b56e7b2fb7689b44947))
* update plan and add utility scripts ([984122c](https://github.com/dungle-scrubs/hisohiso/commit/984122c292e93003c54c6bf0bb2455fe203c1435))


### Maintenance

* add AudioDSP unit tests ([508cee2](https://github.com/dungle-scrubs/hisohiso/commit/508cee28b2368676c50132c7e615dda4e3f8237d))
* add CodeQL workflow for Swift ([a45887e](https://github.com/dungle-scrubs/hisohiso/commit/a45887efbe956a2ad231f39e371da973d522f0ac))
* add CodeQL workflow for Swift ([2e5c8ca](https://github.com/dungle-scrubs/hisohiso/commit/2e5c8cadd89a9b6d3cd2772159b6709f892c3f1b))
* add comprehensive test coverage ([ee67823](https://github.com/dungle-scrubs/hisohiso/commit/ee67823a8120f2388a71acda7023674f08de2ff4))
* add TruffleHog secret scanning workflow ([6fc8d2a](https://github.com/dungle-scrubs/hisohiso/commit/6fc8d2ad231db36f1328fba443078f602b92b334))
* add TruffleHog secret scanning workflow ([4f31945](https://github.com/dungle-scrubs/hisohiso/commit/4f3194573d503ed86e787dbd821d380e91d1cf35))
* minor hardening and thread-safety docs ([7b04351](https://github.com/dungle-scrubs/hisohiso/commit/7b04351e4986429ce38baebdadcdd3d65da97e58))
* **security:** move TruffleHog scanning to pre-push hook ([8988e8f](https://github.com/dungle-scrubs/hisohiso/commit/8988e8fba9b1141a1558c8f48a6f11f6cb7a8e61))
* **security:** move TruffleHog scanning to pre-push hook ([ef604f2](https://github.com/dungle-scrubs/hisohiso/commit/ef604f2c5ea3e8170d32954537f601c6de59d2dc))

## Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
