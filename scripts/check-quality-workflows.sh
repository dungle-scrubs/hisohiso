#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing $path"
}

require_line() {
  local path="$1"
  local pattern="$2"
  rg -q -- "$pattern" "$path" || fail "$path missing pattern: $pattern"
}

ci=".github/workflows/ci.yml"
release=".github/workflows/release.yml"

require_file "$ci"
require_file "$release"

for command in "swift test" "swift build" "swift build -c release" "make lint"; do
  require_line "$ci" "$command"
  require_line "$release" "$command"
done

require_line "$ci" "pull_request:"
require_line "$ci" "macos-14"
require_line "$release" "needs: quality-gate"
require_line "$release" "googleapis/release-please-action@v4"

echo "Quality workflow checks passed"
