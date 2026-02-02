.PHONY: build run test clean lint format setup

# Build the app
build:
	swift build

# Build release
release:
	swift build -c release

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
	brew install swiftlint swiftformat pre-commit
	pre-commit install

# Open in Xcode
xcode:
	open Package.swift

# Show logs (for debugging)
logs:
	tail -f ~/Library/Logs/Hisohiso/hisohiso-*.log
