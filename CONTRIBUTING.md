# Contributing to Hisohiso

Thanks for your interest in contributing.

## Development setup

```bash
git clone https://github.com/dungle-scrubs/hisohiso.git
cd hisohiso
make setup
```

This installs SwiftLint, SwiftFormat, pre-commit hooks, and TruffleHog.

## Requirements

- macOS 14 Sonoma+
- Xcode 15+ or Swift 5.9+ toolchain
- Apple Silicon (M1+)

## Workflow

1. Fork the repo and create a feature branch from `main`
2. Make your changes
3. Run `make test` — all 127 tests must pass
4. Run `make lint` — no warnings allowed (strict mode)
5. Commit using [conventional commits](#commit-messages)
6. Open a pull request against `main`

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/)
for automated changelog generation:

```
feat: add export command
fix: resolve crash on empty input
docs: update README installation section
chore: update dependencies
test: add TextFormatter edge case tests
refactor: extract audio processing to AudioDSP
feat!: change config format (breaking change)
```

## Code style

- **SwiftFormat** — runs automatically via pre-commit hook
  (config: `.swiftformat`)
- **SwiftLint** — runs automatically via pre-commit hook
  (config: `.swiftlint.yml`)
- 4-space indentation, 120-char line width
- Prefer `let` over `var`
- Use strict concurrency (`@Sendable`, `@MainActor`)

## Testing

```bash
make test
```

Tests use XCTest. Add tests for:

- Business logic (TextFormatter, AudioDSP, state machines)
- Protocol conformance
- Edge cases and error paths

Don't add tests for UI code or trivial getters.

## Architecture notes

- **AppKit over SwiftUI** for window management — more reliable in menu bar
  apps
- **Dual hotkey detection** — CGEventTap + NSEvent global monitor as fallback
- **Keep model instances alive** — don't reinitialize per-transcription
- File logging to `~/Library/Logs/Hisohiso/` — tail during development

## Pull requests

- One feature or fix per PR
- Keep PRs focused and reviewable
- Include test coverage for new logic
- Update relevant documentation

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
