#!/usr/bin/env bash
set -euo pipefail

doc="docs/audio-recording-dependency.md"
[[ -f "$doc" ]] || { echo "Missing $doc" >&2; exit 1; }
rg -q 'Decision: keep AudioKit as an optional recorder backend' "$doc"
rg -q '`AudioKit` imports stay inside `AudioKitRecorder.swift`' "$doc"
rg -q 'The default remains `false`' "$doc"
rg -q 'AudioKit.git' Package.swift
rg -q 'case useAudioKit' Sources/Hisohiso/AppSettings.swift
imports="$(rg -n '^import AudioKit$' Sources/Hisohiso || true)"
expected='Sources/Hisohiso/AudioKitRecorder.swift:1:import AudioKit'
if [[ "$imports" != "$expected" ]]; then
  echo "AudioKit must stay isolated to AudioKitRecorder.swift" >&2
  printf '%s\n' "$imports" >&2
  exit 1
fi

echo "AudioKit dependency decision is documented and isolated"
