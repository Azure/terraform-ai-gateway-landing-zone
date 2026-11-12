#!/usr/bin/env bash
# Lists the stacks (in apply order) and access-contract files affected by the
# changes between BASE and HEAD, as JSON for a GitHub Actions matrix.
#   scripts/ci/changed-stacks.sh <base-ref> [env]
# Output: {"stacks":["platform",...],"contracts":["team-a-chatbot",...]}
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${1:-origin/main}"; env="${2:-}"
order=(identity network app-hosting platform gateway-config llm-backend-onboarding access-contracts)
mapfile -t files < <(git diff --name-only "$base"...HEAD)

declare -A hit=()
contracts=()
for f in "${files[@]}"; do
  case "$f" in
    stacks/*/*)
      hit[$(cut -d/ -f2 <<<"$f")]=1 ;;
    modules/*)
      m=$(cut -d/ -f2 <<<"$f")
      for s in $(git grep -l "modules/$m\"" -- 'stacks/*/*.tf' | cut -d/ -f2 | sort -u); do hit[$s]=1; done ;;
    environments/*/common.tfvars|environments/*/backend.hcl)
      [[ -z "$env" || "$f" == environments/$env/* ]] && for s in "${order[@]}"; do hit[$s]=1; done ;;
    environments/*/access-contracts/*.tfvars)
      [[ -z "$env" || "$f" == environments/$env/* ]] && contracts+=("$(basename "$f" .tfvars)") ;;
    environments/*/*.tfvars)
      [[ -z "$env" || "$f" == environments/$env/* ]] && hit[$(basename "$f" .tfvars)]=1 ;;
    logicapp-src/*)
      hit[platform]=1 ;;
  esac
done

stacks=()
for s in "${order[@]}"; do [[ -n "${hit[$s]:-}" && "$s" != access-contracts ]] && stacks+=("$s"); done
# A change to the contracts stack itself re-plans every contract.
if [[ -n "${hit[access-contracts]:-}" && -n "$env" ]]; then
  # Inputs are ignored and restored only in the deployment job. Expand there.
  contracts=("*")
fi
python3 - "${stacks[@]+"${stacks[@]}"}" -- "${contracts[@]+"${contracts[@]}"}" <<'PY'
import json, sys
a = sys.argv[1:]; i = a.index('--')
print(json.dumps({"stacks": a[:i], "contracts": sorted(set(a[i+1:]))}))
PY
