#!/usr/bin/env bash
# =============================================================================
# Auto-import existing Azure resources into Terraform state.
#
# Runs `terraform apply` and, when it fails with "already exists" errors,
# parses each error to extract the Terraform address + Azure resource ID,
# imports them, and retries apply. Repeats until apply succeeds or no new
# imports are detected.
#
# Usage:
#   ./scripts/import-existing.sh <env> [--max-retries N]
#   ./scripts/import-existing.sh dev
# =============================================================================

set -euo pipefail

# Prevent Git Bash / MSYS on Windows from rewriting leading-slash arguments
# (e.g. "/subscriptions/..." Azure resource IDs) into Windows paths like
# "C:/Program Files/Git/subscriptions/..." before terraform.exe sees them.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Python interpreter (Windows Git Bash ships `python`, not `python3`).
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"
else error "Python not found. Install Python 3 and ensure 'python3' or 'python' is on PATH"; fi

ENVIRONMENT="${1:-dev}"
MAX_RETRIES=5
[[ "${2:-}" == "--max-retries" && -n "${3:-}" ]] && MAX_RETRIES="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="${ROOT_DIR}/environments/${ENVIRONMENT}.tfvars"
[[ -f "$TFVARS_FILE" ]] || error "Vars file not found: ${TFVARS_FILE}"

cd "$ROOT_DIR"

# Use a workspace-local temp dir. /tmp paths from `mktemp -t` break when
# Git Bash hands them to native Windows python3 (it resolves "/tmp/foo" as
# "\tmp\foo" on the current drive, which doesn't exist).
TMP_DIR="${ROOT_DIR}/.tf-import-tmp"
mkdir -p "$TMP_DIR"
LOG_FILE="$(mktemp "${TMP_DIR}/tf-apply.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# Path handed to native Windows Python: convert "/c/..." → "C:\..." so it can
# be opened. On Linux/macOS cygpath is absent and the path is used as-is.
if command -v cygpath >/dev/null 2>&1; then
  PY_LOG_FILE="$(cygpath -w "$LOG_FILE")"
else
  PY_LOG_FILE="$LOG_FILE"
fi

attempt=0
while (( attempt < MAX_RETRIES )); do
  attempt=$((attempt + 1))
  info "Apply attempt ${attempt}/${MAX_RETRIES}..."

  # Run apply with -json so we get structured diagnostic events (one JSON
  # object per line) instead of having to scrape human-formatted error blocks
  # with the leading "│ " prefix. We tee the JSON stream to LOG_FILE for
  # parsing and pipe a human-readable rendering to the terminal.
  set +e
  terraform apply -var-file="$TFVARS_FILE" -auto-approve -json \
    2>&1 | tee "$LOG_FILE" \
    | "$PYTHON_BIN" -c "
import json, sys
for line in sys.stdin:
    try:
        evt = json.loads(line)
    except ValueError:
        sys.stdout.write(line); continue
    msg = evt.get('@message', '')
    if evt.get('@level') == 'error':
        sys.stdout.write('ERROR: ' + msg + chr(10))
    elif evt.get('type') in ('apply_start','apply_complete','apply_errored','change_summary'):
        sys.stdout.write(msg + chr(10))
"
  exit_code=${PIPESTATUS[0]}
  set -e

  if [[ $exit_code -eq 0 ]]; then
    success "Apply succeeded on attempt ${attempt}."
    exit 0
  fi

  # Parse the JSON event stream. Each diagnostic error has structured
  # fields (`diagnostic.summarPY_y`, `diagnostic.detail`, `diagnostic.address`),
  # so we only need a small regex against `detail` to pull out the Azure ID
  # or role-assignment GUID — no more multi-line scraping of "│"-prefixed
  # output.
  #
  # Emits two streams to stdout:
  #   IMPORT\t<addr>\t<azure-id>
  #   ROLE\t<addr>\t<guid>
  PARSED="$("$PYTHON_BIN" - "$LOG_FILE" <<'PY'
import json, re, sys, pathlib

ID_RE   = re.compile(r'"(/subscriptions/[^"]+)"\s+already exists')
GUID_RE = re.compile(r'existing role assignment is\s+([A-Za-z0-9\-]+)')

seen = set()
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line or not line.startswith('{'):
        continue
    try:
        evt = json.loads(line)
    except ValueError:
        continue
    if evt.get('@level') != 'error':
        continue
    diag = evt.get('diagnostic') or {}
    addr = diag.get('address') or ''
    summary = diag.get('summary') or ''
    detail  = diag.get('detail') or ''
    if not addr:
        continue
    blob = summary + '\n' + detail

    m = ID_RE.search(blob)
    if m:
        key = ('IMPORT', addr, m.group(1))
        if key not in seen:
            seen.add(key)
            print(f"IMPORT\t{addr}\t{m.group(1)}")
        continue

    m = GUID_RE.search(blob)
    if m:
        key = ('ROLE', addr, m.group(1))
        if key not in seen:
            seen.add(key)
            print(f"ROLE\t{addr}\t{m.group(1)}")
PY
)"

  IMPORTS=()
  ROLE_IMPORTS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    kind="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    case "$kind" in
      IMPORT) IMPORTS+=("$rest") ;;
      ROLE)   ROLE_IMPORTS+=("$rest") ;;
    esac
  done <<< "$PARSED"

  if [[ ${#IMPORTS[@]} -eq 0 && ${#ROLE_IMPORTS[@]} -eq 0 ]]; then
    error "Apply failed and no 'already exists' errors were detected. See output above."
  fi

  total_found=$(( ${#IMPORTS[@]} + ${#ROLE_IMPORTS[@]} ))
  info "Detected ${total_found} resource(s) to import:"
  for line in "${IMPORTS[@]}"; do
    echo "  - ${line%%	*}"
  done
  for line in "${ROLE_IMPORTS[@]}"; do
    echo "  - ${line%%	*} (role assignment)"
  done

  imported_any=0

  # --- Generic "already exists" imports (azurerm + azapi) ---
  for line in "${IMPORTS[@]}"; do
    addr="${line%%	*}"
    rid="${line##*	}"

    # Skip if already in state.
    if terraform state show "$addr" >/dev/null 2>&1; then
      warn "Already in state, skipping: ${addr}"
      continue
    fi

    info "Importing ${addr}"
    info "         <- ${rid}"
    if terraform import -var-file="$TFVARS_FILE" "$addr" "$rid"; then
      success "Imported ${addr}"
      imported_any=1
    else
      warn "Failed to import ${addr} — continuing."
    fi
  done

  # --- RoleAssignmentExists imports ---
  # azurerm_role_assignment import ID format:
  #   <scope>/providers/Microsoft.Authorization/roleAssignments/<guid>
  # We recover <scope> from the planned resource values.
  for line in "${ROLE_IMPORTS[@]}"; do
    addr="${line%%	*}"
    guid="${line##*	}"

    if terraform state show "$addr" >/dev/null 2>&1; then
      warn "Already in state, skipping: ${addr}"
      continue
    fi

    info "Resolving scope for role assignment: ${addr}"
    ra_plan="$(mktemp "${TMP_DIR}/tf-ra-plan.XXXXXX")"
    if ! terraform plan -var-file="$TFVARS_FILE" -target="$addr" -out="$ra_plan" >/dev/null 2>&1; then
      warn "Could not plan ${addr} to resolve scope — skipping."
      rm -f "$ra_plan"
      continue
    fi

    scope=$(terraform show -json "$ra_plan" 2>/dev/null | "$PYTHON_BIN" -c "
import json, sys
addr = sys.argv[1]
data = json.load(sys.stdin)
for rc in data.get('resource_changes', []):
    if rc.get('address') == addr:
        after = (rc.get('change') or {}).get('after') or {}
        print(after.get('scope', ''))
        break
" "$addr")
    rm -f "$ra_plan"

    if [[ -z "$scope" ]]; then
      warn "Empty scope for ${addr} — skipping."
      continue
    fi

    rid="${scope}/providers/Microsoft.Authorization/roleAssignments/${guid}"
    info "Importing ${addr}"
    info "         <- ${rid}"
    if terraform import -var-file="$TFVARS_FILE" "$addr" "$rid"; then
      success "Imported ${addr}"
      imported_any=1
    else
      warn "Failed to import ${addr} — continuing."
    fi
  done

  if [[ $imported_any -eq 0 ]]; then
    error "No new resources were imported on this attempt; aborting to avoid an infinite loop."
  fi
done

error "Reached max retries (${MAX_RETRIES}) without a successful apply."
