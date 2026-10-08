#!/usr/bin/env bash
# Markdown summary of a saved plan (for $GITHUB_STEP_SUMMARY). Fails when the
# plan deletes or replaces a protected resource type (state-bearing services).
#   scripts/ci/plan-summary.sh <stack dir> <label>     (expects <stack dir>/tfplan)
set -euo pipefail
dir="$1"; label="${2:-$1}"
json=$(terraform -chdir="$dir" show -json tfplan)
count() { jq "[.resource_changes[]? | select(.change.actions | $1)] | length" <<<"$json"; }
add=$(count 'index("create") and (index("delete") | not)')
chg=$(count 'index("update")')
rep=$(count 'index("create") and index("delete")')
del=$(count 'index("delete") and (index("create") | not)')
echo "### $label"
echo "| add | change | replace | destroy |"
echo "|---:|---:|---:|---:|"
echo "| $add | $chg | $rep | $del |"
protected='api_management$|key_vault$|cosmosdb_account|eventhub_namespace|cognitive_account|resource_group$|hostingEnvironments|Microsoft.ApiManagement/service@|Microsoft.CognitiveServices/accounts@'
bad=$(jq -r --arg re "$protected" '.resource_changes[]? | select((.change.actions | index("delete")) and ((.type + " " + (.change.before.type // "")) | test($re))) | .address' <<<"$json")
if [[ -n "$bad" ]]; then
  echo ""
  echo "**Blocked: the plan deletes or replaces protected resources:**"
  sed 's/^/- `/; s/$/`/' <<<"$bad"
  exit 1
fi
