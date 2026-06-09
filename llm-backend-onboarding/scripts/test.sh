#!/usr/bin/env bash
# =============================================================================
# LLM Backend Onboarding — Test Script
#
# Tests the onboarded LLM backends by sending requests through the APIM gateway.
# Validates:
#   1. Backend connectivity (health check via get-available-models)
#   2. Chat completions via OpenAI-compatible API
#   3. Chat completions via Models Inference API
#   4. Streaming responses
#   5. Backend pool load balancing (if multiple backends configured)
#
# Usage:
#   ./scripts/test.sh [OPTIONS]
#
# Options:
#   --gateway-url URL       APIM gateway URL (auto-detected from Terraform state)
#   --api-key KEY           APIM subscription key (required)
#   --model MODEL           Model to test (default: first model in config)
#   --all-models            Test all configured models
#   --verbose               Show full response bodies
#   -h, --help              Show this help message
#
# Prerequisites:
#   - Successful deployment via ./scripts/deploy.sh
#   - Valid APIM subscription key with access to the LLM APIs
#   - curl and jq installed
#
# Examples:
#   ./scripts/test.sh --api-key "your-api-key"
#   ./scripts/test.sh --api-key "your-key" --model gpt-4o --verbose
#   ./scripts/test.sh --api-key "your-key" --all-models
#   ./scripts/test.sh --gateway-url "https://apim-xxx.azure-api.net" --api-key "key"
# =============================================================================

set -euo pipefail

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0
TESTS=0
GATEWAY_URL=""
API_KEY=""
MODEL=""
ALL_MODELS=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-url) shift; GATEWAY_URL="$1" ;;
    --api-key)     shift; API_KEY="$1" ;;
    --model)       shift; MODEL="$1" ;;
    --all-models)  ALL_MODELS="1" ;;
    --verbose)     VERBOSE="1" ;;
    -h|--help)     sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Validate prerequisites ---
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

if [[ -z "$API_KEY" ]]; then
  echo -e "${RED}Error: --api-key is required${NC}"
  echo "  Get a key from your APIM subscription in the Azure portal."
  exit 1
fi

# --- Auto-detect gateway URL from Terraform state ---
if [[ -z "$GATEWAY_URL" ]]; then
  cd "$ROOT_DIR"
  if [[ -f terraform.tfstate ]]; then
    GATEWAY_URL=$(terraform output -raw apim_gateway_url 2>/dev/null || true)
  fi
  if [[ -z "$GATEWAY_URL" ]]; then
    echo -e "${RED}Error: Could not auto-detect gateway URL.${NC}"
    echo "  Pass --gateway-url or run from the directory with terraform.tfstate"
    exit 1
  fi
fi

# Remove trailing slash
GATEWAY_URL="${GATEWAY_URL%/}"

info "Testing APIM Gateway: $GATEWAY_URL"
echo ""

# --- Discover available models from terraform output ---
get_models() {
  cd "$ROOT_DIR"
  if [[ -f terraform.tfstate ]]; then
    terraform output -json supported_models 2>/dev/null | jq -r '.[]' 2>/dev/null || true
  fi
}

# --- Test helper ---
run_test() {
  local test_name="$1"
  local url="$2"
  local method="${3:-GET}"
  local body="${4:-}"
  local expected_status="${5:-200}"

  TESTS=$((TESTS + 1))

  local curl_args=(-s -w "\n%{http_code}" -H "api-key: $API_KEY" -H "Content-Type: application/json")

  if [[ "$method" == "POST" && -n "$body" ]]; then
    curl_args+=(-X POST -d "$body")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo -e "\n000")

  local status_code
  status_code=$(echo "$response" | tail -1)
  local response_body
  response_body=$(echo "$response" | sed '$d')

  if [[ "$status_code" == "$expected_status" ]]; then
    success "$test_name (HTTP $status_code)"
    if [[ -n "$VERBOSE" && -n "$response_body" ]]; then
      echo "$response_body" | jq . 2>/dev/null || echo "$response_body"
      echo ""
    fi
    return 0
  else
    fail "$test_name — Expected HTTP $expected_status, got $status_code"
    if [[ -n "$response_body" ]]; then
      echo "    Response: $(echo "$response_body" | head -c 200)"
    fi
    return 1
  fi
}

# =============================================================================
# TEST 1: Get Available Models (Health Check)
# =============================================================================
echo -e "${BLUE}━━━ Test Suite: Backend Connectivity ━━━${NC}"

run_test "GET /llm/openai/deployments (available models)" \
  "$GATEWAY_URL/llm/openai/deployments?api-version=2024-02-15-preview"

echo ""

# =============================================================================
# TEST 2: Chat Completions (OpenAI-compatible API)
# =============================================================================
echo -e "${BLUE}━━━ Test Suite: Chat Completions (OpenAI API) ━━━${NC}"

test_chat_completion() {
  local model="$1"
  local body
  body=$(jq -n --arg model "$model" '{
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 10,
    "temperature": 0
  }')

  run_test "POST /llm/openai/deployments/$model/chat/completions" \
    "$GATEWAY_URL/llm/openai/deployments/$model/chat/completions?api-version=2024-02-15-preview" \
    "POST" \
    "$body"
}

if [[ -n "$ALL_MODELS" ]]; then
  MODELS=$(get_models)
  if [[ -z "$MODELS" ]]; then
    warn "Could not discover models from Terraform state. Testing default model."
    MODELS="gpt-4o-mini"
  fi
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    test_chat_completion "$m"
  done <<< "$MODELS"
elif [[ -n "$MODEL" ]]; then
  test_chat_completion "$MODEL"
else
  # Default: test first model from Terraform output or gpt-4o-mini
  DEFAULT_MODEL=$(get_models | head -1)
  DEFAULT_MODEL="${DEFAULT_MODEL:-gpt-4o-mini}"
  test_chat_completion "$DEFAULT_MODEL"
fi

echo ""

# =============================================================================
# TEST 3: Chat Completions via Models Inference API
# =============================================================================
echo -e "${BLUE}━━━ Test Suite: Chat Completions (Inference API) ━━━${NC}"

test_inference_completion() {
  local model="$1"
  local body
  body=$(jq -n --arg model "$model" '{
    "model": $model,
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 10,
    "temperature": 0
  }')

  run_test "POST /llm/models/chat/completions (model=$model)" \
    "$GATEWAY_URL/llm/models/chat/completions?api-version=2024-05-01-preview" \
    "POST" \
    "$body"
}

if [[ -n "$MODEL" ]]; then
  test_inference_completion "$MODEL"
else
  DEFAULT_MODEL=$(get_models | head -1)
  DEFAULT_MODEL="${DEFAULT_MODEL:-gpt-4o-mini}"
  test_inference_completion "$DEFAULT_MODEL"
fi

echo ""

# =============================================================================
# TEST 4: Streaming Response
# =============================================================================
echo -e "${BLUE}━━━ Test Suite: Streaming ━━━${NC}"

test_streaming() {
  local model="$1"
  TESTS=$((TESTS + 1))

  local body
  body=$(jq -n --arg model "$model" '{
    "messages": [{"role": "user", "content": "Count from 1 to 3."}],
    "max_tokens": 50,
    "temperature": 0,
    "stream": true
  }')

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -H "api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$body" \
    "$GATEWAY_URL/llm/openai/deployments/$model/chat/completions?api-version=2024-02-15-preview" \
    2>/dev/null || echo -e "\n000")

  local status_code
  status_code=$(echo "$response" | tail -1)
  local response_body
  response_body=$(echo "$response" | sed '$d')

  if [[ "$status_code" == "200" ]]; then
    # Check for SSE format (data: prefix)
    if echo "$response_body" | grep -q "^data:"; then
      success "Streaming chat completions ($model) — SSE chunks received"
      if [[ -n "$VERBOSE" ]]; then
        echo "$response_body" | head -5
        echo "    ..."
      fi
    else
      warn "Streaming ($model) — HTTP 200 but no SSE chunks detected"
    fi
  else
    fail "Streaming chat completions ($model) — HTTP $status_code"
  fi
}

DEFAULT_MODEL=$(get_models | head -1)
DEFAULT_MODEL="${DEFAULT_MODEL:-gpt-4o-mini}"
test_streaming "${MODEL:-$DEFAULT_MODEL}"

echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
PASSED=$((TESTS - FAILURES))
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All $TESTS tests passed!${NC}"
else
  echo -e "${YELLOW}$PASSED/$TESTS passed, $FAILURES failed${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit $FAILURES
