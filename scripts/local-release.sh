#!/usr/bin/env bash
# Cut a release locally: build the signed .app bundle, zip it, and attach it to
# the GitHub release for the latest pushed version tag (creating the release if
# it does not exist yet). Tag first, e.g.:
#   git tag -a v0.2.9 -m v0.2.9 && git push origin v0.2.9
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Resolve the latest pushed version tag
git fetch --tags --quiet
TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -z "${TAG}" ]]; then
  echo "No tags found. Create and push a version tag first (e.g. git tag v0.2.9 && git push origin v0.2.9)." >&2
  exit 1
fi
VERSION="${TAG#v}"
echo "==> Release: ${TAG} (${VERSION})"

# Build from the tagged commit
git checkout "${TAG}" --quiet

# 1. Build .app bundle
echo "==> Building app bundle..."
"${ROOT_DIR}/scripts/build-app-bundle.sh" "${TAG}" dist

# 2. Package as zip
ASSET_NAME="hisohiso-${TAG}-darwin-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Hisohiso.app "dist/${ASSET_NAME}"
APP_SHA256="$(shasum -a 256 "dist/${ASSET_NAME}" | awk '{print $1}')"
echo "==> Asset: ${ASSET_NAME} (sha256: ${APP_SHA256})"

# 3. Create the release if it doesn't exist yet, then attach the asset
echo "==> Publishing release ${TAG}..."
gh release view "${TAG}" >/dev/null 2>&1 || gh release create "${TAG}" \
  --title "${TAG}" \
  --notes "Hisohiso ${TAG} — local-first macOS dictation. Self-signed (not notarized): right-click the app → Open on first launch."
gh release upload "${TAG}" "dist/${ASSET_NAME}" --clobber

echo ""
echo "==> Done! Released ${TAG}"
echo "    Asset:  ${ASSET_NAME}"
echo "    SHA256: ${APP_SHA256}"

# Return to previous branch
git checkout - --quiet
