#!/usr/bin/env bash
# Run locally after merging a release-please PR.
# Builds the .app bundle and uploads it to the GitHub release.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Resolve the latest release tag
TAG=$(gh release list --limit 1 --json tagName -q '.[0].tagName')
if [[ -z "${TAG}" ]]; then
  echo "No GitHub release found. Has the release-please PR been merged?" >&2
  exit 1
fi
VERSION="${TAG#v}"
echo "==> Release: ${TAG} (${VERSION})"

# Ensure we're on the right commit
git fetch --tags
git checkout "${TAG}" --quiet

# 1. Build .app bundle
echo "==> Building app bundle..."
"${ROOT_DIR}/scripts/build-app-bundle.sh" "${TAG}" dist

# 2. Package as zip
ASSET_NAME="hisohiso-${TAG}-darwin-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Hisohiso.app "dist/${ASSET_NAME}"
APP_SHA256="$(shasum -a 256 "dist/${ASSET_NAME}" | awk '{print $1}')"
echo "==> Asset: ${ASSET_NAME} (sha256: ${APP_SHA256})"

# 3. Upload to GitHub release
echo "==> Uploading to release ${TAG}..."
gh release upload "${TAG}" "dist/${ASSET_NAME}" --clobber

echo ""
echo "==> Done! Released ${TAG}"
echo "    Asset:  ${ASSET_NAME}"
echo "    SHA256: ${APP_SHA256}"

# Return to previous branch
git checkout - --quiet
