.PHONY: build run test clean lint format setup xcode logs app-bundle install-agent uninstall-agent agent-status crashes

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

# Lint with SwiftLint
lint:
	swiftlint --config .swiftlint.yml

# Format with SwiftFormat
format:
	swiftformat --config .swiftformat .

# Setup development environment
setup:
	brew install swiftlint swiftformat pre-commit trufflehog
	pre-commit install
	pre-commit install --hook-type pre-push

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
	@echo "  Binary: /opt/homebrew/bin/hisohiso"
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

# Build release and install to Homebrew bin (replaces current binary)
install: release
	@chmod u+w /opt/homebrew/Cellar/hisohiso/*/bin/hisohiso 2>/dev/null || true
	@cp .build/release/Hisohiso /opt/homebrew/Cellar/hisohiso/*/bin/hisohiso
	@echo "✓ Installed release build to $$(readlink -f /opt/homebrew/bin/hisohiso)"

# List crash archives
crashes:
	@ls -lt ~/Library/Logs/Hisohiso/crashes/ 2>/dev/null || echo "No crash archives found"
