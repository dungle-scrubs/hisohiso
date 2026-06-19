#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity for local Hisohiso builds.
#
# Why this exists: ad-hoc signing (`codesign -s -`) gives the binary a fresh
# cdhash on every rebuild, so macOS TCC treats each build as a brand-new app
# and silently drops the Accessibility / Input Monitoring grants the Globe key
# depends on. Signing with a real (even self-signed) certificate makes the
# code's designated requirement stable across rebuilds, so those grants persist.
#
# The identity lives in a dedicated keychain with a known, non-secret password
# so signing stays fully scriptable (no GUI prompts, no login-keychain password,
# no sudo). Re-running this script is a no-op if the identity already exists.
set -euo pipefail

IDENTITY_NAME="${HISOHISO_CODESIGN_IDENTITY:-Hisohiso Local Signing}"
KEYCHAIN="${HOME}/Library/Keychains/hisohiso-signing.keychain-db"
KEYCHAIN_PASSWORD="hisohiso-local"
# Apple's `security import` rejects empty-password PKCS#12 MACs, so the
# transient .p12 needs a real (non-secret, local-only) passphrase.
P12_PASSWORD="hisohiso-local"

# Already present? Nothing to do. (Omit -v: a self-signed cert is untrusted and
# so not "valid" per policy, but codesign can still use it by name.)
if security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "${IDENTITY_NAME}"; then
  echo "Signing identity already present: ${IDENTITY_NAME}"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# 1. Generate a self-signed cert with the code-signing extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "${WORK_DIR}/key.pem" \
  -out "${WORK_DIR}/cert.pem" \
  -subj "/CN=${IDENTITY_NAME}" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# Apple's `security import` cannot read PKCS#12 files that use OpenSSL 3.x's
# default MAC/PBE algorithms, so force the legacy SHA1/3DES scheme it expects.
openssl pkcs12 -export \
  -inkey "${WORK_DIR}/key.pem" \
  -in "${WORK_DIR}/cert.pem" \
  -out "${WORK_DIR}/identity.p12" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 -legacy \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

# 2. Create (or reuse) the dedicated signing keychain.
if [[ ! -f "${KEYCHAIN}" ]]; then
  security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
fi
security set-keychain-settings "${KEYCHAIN}"           # no auto-lock timeout
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"

# 3. Import the identity and let codesign use it without prompting.
security import "${WORK_DIR}/identity.p12" -k "${KEYCHAIN}" -P "${P12_PASSWORD}" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null

# 4. Add the keychain to the search list so codesign can find the identity.
EXISTING_KEYCHAINS="$(security list-keychains -d user | sed -e 's/[" ]//g')"
if ! grep -qF "${KEYCHAIN}" <<<"${EXISTING_KEYCHAINS}"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s ${EXISTING_KEYCHAINS} "${KEYCHAIN}"
fi

echo "Created signing identity: ${IDENTITY_NAME}"
echo "Keychain: ${KEYCHAIN}"
security find-identity -p codesigning "${KEYCHAIN}" | grep "${IDENTITY_NAME}" || true
