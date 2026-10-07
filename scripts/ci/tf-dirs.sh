#!/usr/bin/env bash
# Lists every directory that contains Terraform configuration (roots and modules).
# Usage: scripts/ci/tf-dirs.sh            -> one directory per line
#        scripts/ci/tf-dirs.sh --json     -> JSON array (for a GitHub Actions matrix)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
dirs=$(git ls-files -co --exclude-standard -- '*.tf' | while IFS= read -r p; do [[ -e "$p" ]] && dirname "$p"; done | sort -u)
if [[ "${1:-}" == "--json" ]]; then
  printf '%s\n' $dirs | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
else
  printf '%s\n' $dirs
fi
