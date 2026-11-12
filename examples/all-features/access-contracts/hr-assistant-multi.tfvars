# One product that grants a MIX of asset types: LLM inference APIs and tools (MCP).
# APIM doesn't expose the API type to policy, so the product policy classifies each request
# by API name (the set-asset-kind fragment of stacks/gateway-config) and applies different
# controls per type:
#   LLM   model RBAC + token limit        (allowed_models, token_limit)
#   tool  request rate limit + call quota (tool_limit)
# Any API that isn't listed as a tool or agent is an LLM API.
use_case = {
  business_unit = "HR"
  use_case_name = "Assistant"
  environment   = "PROD"
}

# The first API is the product's endpoint (the secret and any Foundry connection): put the LLM API first.
api_name_mapping = {
  MULTI = ["universal-llm-api", "azure-openai-api", "weather-mcp", "ms-learn-mcp"]
}

services = [
  {
    code                 = "MULTI" # LLM / TOOL / AGENT for one asset type, MULTI for a mix (any code works)
    endpoint_secret_name = "HR-MULTI-ENDPOINT"
    api_key_secret_name  = "HR-MULTI-KEY"

    # LLM controls: they apply to the LLM APIs only, never to tool calls.
    allowed_models          = ["fast", "balanced"]
    token_limit             = { tokens_per_minute = 20000, token_quota = 2000000, token_quota_period = "Monthly" }
    enable_response_headers = true

    # Tool (MCP) controls: the granted tool APIs by APIM API name (they must be in api_name_mapping),
    # throttled by request count because LLM tokens don't exist for a tool call.
    tool_apis  = ["weather-mcp", "ms-learn-mcp"]
    tool_limit = { calls_per_minute = 60, call_quota = 10000, call_quota_period = "Monthly" }

    # Agents (A2A) work the same way. This repository doesn't publish agent APIs: once yours are in
    # APIM, add them to api_name_mapping above and list them here.
    # agent_apis  = ["hr-chat-agent"]
    # agent_limit = { calls_per_minute = 30, call_quota = 5000, call_quota_period = "Monthly" }
  },
]

product_terms = "HR assistant: models and tools"

key_vault = { enabled = true }
