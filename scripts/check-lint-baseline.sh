#!/usr/bin/env bash
set -euo pipefail

output="$(swiftlint --config .swiftlint.yml 2>&1 || true)"
unexpected="$(printf '%s\n' "$output" | rg 'warning:|error:' || true)"
allowed='Sources/Hisohiso/UI/HistoryPaletteWindow.swift:78:13: warning: Function Body Length Violation'

if [[ -n "$unexpected" ]]; then
  unexpected="$(printf '%s\n' "$unexpected" | rg -v -F "$allowed" || true)"
fi

if [[ -n "$unexpected" ]]; then
  echo "Unexpected SwiftLint findings:" >&2
  printf '%s\n' "$unexpected" >&2
  exit 1
fi

printf '%s\n' "$output"
echo "SwiftLint baseline check passed"
