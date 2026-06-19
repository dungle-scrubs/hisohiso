#!/usr/bin/env bash
set -euo pipefail

inventory="${1:-docs/concurrency-escape-hatches.tsv}"
[[ -f "$inventory" ]] || {
  echo "ERROR: missing inventory: $inventory" >&2
  exit 1
}

current="$(mktemp)"
expected="$(mktemp)"
trap 'rm -f "$current" "$expected"' EXIT

rg -n '@unchecked Sendable|nonisolated\(unsafe\)' Sources/Hisohiso --glob '*.swift' \
  | awk -F: '
      /^[^:]+:[0-9]+:[[:space:]]*\/\// { next }
      /@unchecked Sendable/ {
        line=$3
        sub(/.*(class|struct)[[:space:]]+/, "", line)
        sub(/[:<(].*/, "", line)
        print $1 "\tunchecked-sendable\t" line
        next
      }
      /nonisolated\(unsafe\)/ {
        line=$3
        sub(/.*var[[:space:]]+/, "", line)
        sub(/[[:space:]=:].*/, "", line)
        print $1 "\tnonisolated-unsafe\t" line
      }
    ' \
  | sort > "$current"

awk -F '\t' 'NR > 1 { print $1 "\t" $2 "\t" $3 }' "$inventory" | sort > "$expected"

if ! diff -u "$expected" "$current"; then
  cat >&2 <<'EOF'
ERROR: concurrency escape hatch inventory is stale.
Update docs/concurrency-escape-hatches.tsv with every @unchecked Sendable and
nonisolated(unsafe) occurrence, including classification and rationale.
EOF
  exit 1
fi

awk -F '\t' '
  NR == 1 { next }
  NF < 5 || $4 !~ /^(remove|narrow|justified)$/ || $5 == "" {
    printf "ERROR: invalid inventory row %d\n", NR > "/dev/stderr"
    bad = 1
  }
  END { exit bad }
' "$inventory"

echo "Concurrency escape hatch inventory is current"
