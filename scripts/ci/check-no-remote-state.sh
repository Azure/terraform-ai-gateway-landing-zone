#!/usr/bin/env bash
# R6: stacks find each other's resources by name, never through terraform_remote_state.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if git ls-files -- '*.tf' | xargs grep -n 'terraform_remote_state'; then
  echo "::error::terraform_remote_state is not allowed (use data sources by deterministic name, review 7.7)"
  exit 1
fi
echo "no remote state OK"
