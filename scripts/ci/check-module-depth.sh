#!/usr/bin/env bash
# R1: stack -> custom module -> AVM module. A custom module never calls another
# custom module (no relative module sources inside modules/).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
hits=$(git ls-files -- 'modules/*.tf' 'modules/**/*.tf' | xargs grep -nE '^\s*source\s*=\s*"\.\.?/' || true)
# examples/ inside a module may call the module itself.
hits=$(grep -v '/examples/' <<<"$hits" || true)
if [[ -n "$hits" ]]; then
  echo "$hits" | sed 's/^/::error::custom module calls another local module: /'
  exit 1
fi
echo "module depth OK"
