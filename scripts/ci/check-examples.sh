#!/usr/bin/env bash
# Every example (examples/<scenario>/<stack>.tfvars) plans against its stack with
# mocked providers (stacks/<stack>/tests/examples.tftest.hcl). <...> placeholders
# are replaced with dummy values first. Run after `terraform init -backend=false`
# in every stack (CI's validate job, or: task test).
#   scripts/ci/check-examples.sh [scenario...]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
scenarios=("$@"); [[ ${#scenarios[@]} -gt 0 ]] || mapfile -t scenarios < <(ls examples)

fill() {
  sed -E \
    -e 's/<workload-subscription-id>/00000000-0000-0000-0000-000000000002/g' \
    -e 's#/subscriptions/<[a-z-]*sub>/#/subscriptions/00000000-0000-0000-0000-000000000002/#g' \
    -e 's/<your-public-ip>/203.0.113.10/g' \
    -e 's/<hub-firewall-private-ip>/10.0.0.4/g' \
    -e 's/<[a-z-]*(principal-id|object-id|tenant-id|client-id)>/00000000-0000-0000-0000-0000000000a1/g' \
    -e 's#<owner>/<repo>#contoso/ai-gateway#g' \
    -e 's/<([a-z0-9-]+)>/\1/g' "$1"
}

for sc in "${scenarios[@]}"; do
  d="examples/$sc"
  fill "$d/common.tfvars" > "$tmp/common.tfvars"
  for f in "$d"/*.tfvars "$d"/access-contracts/*.tfvars; do
    [[ -e "$f" ]] || continue
    name=$(basename "$f" .tfvars)
    [[ "$name" == common ]] && continue
    stack="$name"; [[ "$f" == */access-contracts/* ]] && stack=access-contracts
    fill "$f" > "$tmp/stack.tfvars"
    if out=$(cd "stacks/$stack" && terraform test -no-color -filter=tests/examples.tftest.hcl -var-file="$tmp/common.tfvars" -var-file="$tmp/stack.tfvars" 2>&1); then
      echo "ok    $sc/$name"
    else
      echo "::error file=$f::example doesn't plan against stacks/$stack"; grep -E 'Error|error_message|on .* line' <<<"$out" | head -20; fail=1
    fi
  done
done
exit $fail
