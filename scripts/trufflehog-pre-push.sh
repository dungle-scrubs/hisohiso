#!/usr/bin/env bash
set -euo pipefail

if ! command -v trufflehog >/dev/null 2>&1; then
  echo "trufflehog is required. Install it with: brew install trufflehog"
  exit 1
fi

from_ref="${PRE_COMMIT_FROM_REF:-}"
if [[ -z "${from_ref}" || "${from_ref}" =~ ^0+$ ]]; then
  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    from_ref="$(git rev-parse HEAD~1)"
  else
    from_ref="$(git rev-list --max-parents=0 HEAD)"
  fi
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${branch}" == "HEAD" ]]; then
  branch="HEAD"
fi

exec trufflehog git "file://$(pwd)" \
  --since-commit "${from_ref}" \
  --branch "${branch}" \
  --results=verified,unknown \
  --fail \
  --no-update
