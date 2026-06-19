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

# Bundle linked frameworks (e.g. ESpeakNG.framework). The binary loads these via
# @rpath, so they must travel inside the .app or it crashes on launch with a
# dyld "Library not loaded" error. @loader_path/../Frameworks resolves them
# relative to the executable in Contents/MacOS.
FRAMEWORKS=$(find "${BIN_DIR}" -maxdepth 1 -type d -name '*.framework')
if [[ -n "${FRAMEWORKS}" ]]; then
  mkdir -p "${APP_DIR}/Contents/Frameworks"
  while IFS= read -r framework; do
    cp -R "${framework}" "${APP_DIR}/Contents/Frameworks/"
  done <<<"${FRAMEWORKS}"
  install_name_tool -add_rpath @loader_path/../Frameworks "${APP_DIR}/Contents/MacOS/Hisohiso"
fi

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
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.hisohiso.app</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>hisohiso</string>
      </array>
    </dict>
  </array>
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

# Sign with a stable identity when one is available. Ad-hoc signing (`-`) gives
# the binary a fresh cdhash on every build, so macOS TCC drops the Accessibility
# / Input Monitoring grants the Globe key needs, breaking dictation after every
# rebuild. A self-signed identity keeps the code's designated requirement stable
# across builds so those grants persist. Run scripts/create-signing-cert.sh once
# to create the default identity.
SIGNING_KEYCHAIN="${HOME}/Library/Keychains/hisohiso-signing.keychain-db"
SIGN_IDENTITY="${HISOHISO_CODESIGN_IDENTITY:-Hisohiso Local Signing}"
CODESIGN_ARGS=()
if security find-identity -p codesigning "${SIGNING_KEYCHAIN}" 2>/dev/null | grep -qF "${SIGN_IDENTITY}"; then
  echo "Signing with stable identity: ${SIGN_IDENTITY}"
  CODESIGN_ARGS=(--sign "${SIGN_IDENTITY}" --keychain "${SIGNING_KEYCHAIN}")
else
  echo "WARNING: signing identity '${SIGN_IDENTITY}' not found; falling back to ad-hoc." >&2
  echo "         The Globe key will lose its Accessibility grant on each rebuild." >&2
  echo "         Run scripts/create-signing-cert.sh once to fix this permanently." >&2
  CODESIGN_ARGS=(--sign -)
fi

# Sign nested frameworks before the outer bundle (inside-out), then verify.
if [[ -d "${APP_DIR}/Contents/Frameworks" ]]; then
  find "${APP_DIR}/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 |
    while IFS= read -r -d '' framework; do
      codesign --force "${CODESIGN_ARGS[@]}" "${framework}"
    done
fi
codesign --force --deep "${CODESIGN_ARGS[@]}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Built app bundle: ${APP_DIR}"
