# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, please report vulnerabilities via
[GitHub Security Advisories](https://github.com/dungle-scrubs/hisohiso/security/advisories/new).

You will receive a response within 72 hours. If the vulnerability is confirmed,
a fix will be developed privately and released as a patch.

## Scope

Security issues in scope:

- Secret leakage (API keys, tokens, credentials)
- Privilege escalation via Accessibility/Input Monitoring APIs
- Audio data exfiltration or unauthorized recording
- Keychain storage vulnerabilities
- Code injection via text insertion
- Dependency vulnerabilities (WhisperKit, FluidAudio, AudioKit)

## Security practices

- API keys stored in macOS Keychain (never in files or UserDefaults)
- TruffleHog secret scanning on every push and pull request
- CodeQL static analysis on every push to `main`
- No network calls unless cloud transcription is explicitly enabled
- All transcription runs on-device by default
