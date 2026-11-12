#!/usr/bin/env bash
# R4: an AVM module is pinned to exactly one version across the repository.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
pairs=$(git ls-files -- '*.tf' | xargs awk '
  /^[[:space:]]*source[[:space:]]*=[[:space:]]*"Azure\/avm-/ { match($0, /"[^"]+"/); src = substr($0, RSTART + 1, RLENGTH - 2); sub(/\/\/.*/, "", src); next_is = 1; next }
  next_is && /^[[:space:]]*version[[:space:]]*=/ { match($0, /"[^"]+"/); print src " " substr($0, RSTART + 1, RLENGTH - 2); next_is = 0 }
' | sort -u)
dups=$(awk '{print $1}' <<<"$pairs" | uniq -d)
if [[ -n "$dups" ]]; then
  for m in $dups; do echo "::error::$m is pinned to more than one version: $(grep "^$m " <<<"$pairs" | awk '{print $2}' | tr '\n' ' ')"; done
  exit 1
fi
echo "AVM versions OK ($(wc -l <<<"$pairs" | tr -d ' ') modules)"
