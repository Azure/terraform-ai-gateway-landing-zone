#!/usr/bin/env bash
# Every stack has the same variables.common.tf and naming.tf (review 7.5.0).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
for f in variables.common.tf naming.tf; do
  ref="stacks/bootstrap/$f"
  for d in stacks/*/; do
    s="${d}${f}"
    if [[ ! -f "$s" ]]; then echo "::error file=$s::missing (copy $ref)"; fail=1; continue; fi
    if ! diff -q "$ref" "$s" >/dev/null; then echo "::error file=$s::differs from $ref (keep the common files identical)"; fail=1; fi
  done
done
[[ $fail -eq 0 ]] && echo "common stack files OK"
exit $fail
