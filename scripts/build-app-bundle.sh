#!/usr/bin/env bash
set -euo pipefail

VERSION_INPUT="${1:-}"
OUTPUT_DIR="${2:-dist}"

if [[ -z "${VERSION_INPUT}" ]]; then
  echo "Usage: $0 <version|tag> [output-dir]" >&2
  exit 1
fi

VERSION="${VERSION_INPUT#v}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/${OUTPUT_DIR}/Hisohiso.app"

cd "${ROOT_DIR}"

swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_DIR}/Hisohiso" "${APP_DIR}/Contents/MacOS/Hisohiso"
chmod +x "${APP_DIR}/Contents/MacOS/Hisohiso"

find "${BIN_DIR}" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "${APP_DIR}/Contents/Resources/" \;

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Hisohiso</string>
  <key>CFBundleExecutable</key>
  <string>Hisohiso</string>
  <key>CFBundleIdentifier</key>
  <string>com.hisohiso.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Hisohiso</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Hisohiso needs microphone access to record audio for dictation.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built app bundle: ${APP_DIR}"
