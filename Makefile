.PHONY: build run test clean lint concurrency-escapes audiokit-decision validate format setup xcode logs app-bundle install-agent uninstall-agent agent-status crashes

PLIST_NAME := com.hisohiso.app.plist
PLIST_SRC  := Resources/$(PLIST_NAME)
PLIST_DEST := ~/Library/LaunchAgents/$(PLIST_NAME)

# Build the app
build:
	swift build

# Build release
release:
	swift build -c release

# Build unsigned .app bundle in dist/ (example: make app-bundle VERSION=0.2.4)
app-bundle:
	@test -n "$(VERSION)" || (echo "VERSION is required (e.g. make app-bundle VERSION=0.2.4)" && exit 1)
	./scripts/build-app-bundle.sh "$(VERSION)" dist

# Run the app
run:
	swift run

# Run tests
test:
	swift test

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Lint with SwiftLint and fail on findings outside the tracked baseline.
lint:
	./scripts/check-lint-baseline.sh

# Verify concurrency escape hatch inventory stays classified.
concurrency-escapes:
	./scripts/check-concurrency-escapes.sh

# Verify the optional AudioKit dependency remains documented and isolated.
audiokit-decision:
	./scripts/check-audiokit-decision.sh

# Run the local quality gate in the same order as CI.
validate:
	swift test
	swift build
	swift build -c release
	$(MAKE) lint
	$(MAKE) concurrency-escapes
	$(MAKE) audiokit-decision

# Format with SwiftFormat
format:
	swiftformat --config .swiftformat .

# Setup development environment
setup:
	brew install swiftlint swiftformat lefthook trufflehog
	lefthook install

# Open in Xcode
xcode:
	open Package.swift

# Show logs (for debugging)
logs:
	tail -f ~/Library/Logs/Hisohiso/hisohiso-*.log

# Install launchd agent (auto-restart on crash, run at login)
install-agent:
	@mkdir -p ~/Library/LaunchAgents
	@cp $(PLIST_SRC) $(PLIST_DEST)
	@launchctl unload $(PLIST_DEST) 2>/dev/null || true
	@launchctl load $(PLIST_DEST)
	@echo "✓ Hisohiso launch agent installed and loaded"
	@echo "  Binary: /Applications/Hisohiso.app/Contents/MacOS/Hisohiso"
	@echo "  Plist:  $(PLIST_DEST)"
	@echo "  Status: make agent-status"

# Uninstall launchd agent
uninstall-agent:
	@launchctl unload $(PLIST_DEST) 2>/dev/null || true
	@rm -f $(PLIST_DEST)
	@echo "✓ Hisohiso launch agent uninstalled"

# Check agent status
agent-status:
	@launchctl list com.hisohiso.app 2>/dev/null || echo "Agent not loaded"
	@echo "---"
	@echo "Launchd stdout: /tmp/hisohiso-launchd.out"
	@echo "Launchd stderr: /tmp/hisohiso-launchd.err"
	@echo "App logs:       ~/Library/Logs/Hisohiso/"
	@echo "Crash archives: ~/Library/Logs/Hisohiso/crashes/"

# List crash archives
crashes:
	@ls -lt ~/Library/Logs/Hisohiso/crashes/ 2>/dev/null || echo "No crash archives found"
