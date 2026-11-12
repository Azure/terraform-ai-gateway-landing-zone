# A contract for tools (MCP) only: no model access, every call throttled by request count.
# The product still uses the asset-type-aware policy (tool_apis), so the LLM rules never run
# for these APIs.
use_case = {
  business_unit = "Ops"
  use_case_name = "Tools"
  environment   = "PROD"
}

api_name_mapping = {
  TOOL = ["weather-mcp", "ms-learn-mcp"]
}

services = [
  {
    code                 = "TOOL"
    endpoint_secret_name = "OPS-TOOL-ENDPOINT"
    api_key_secret_name  = "OPS-TOOL-KEY"

    tool_apis  = ["weather-mcp", "ms-learn-mcp"]
    tool_limit = { calls_per_minute = 30, call_quota = 1000, call_quota_period = "Daily" }
  },
]

product_terms = "Ops tools"

key_vault = { enabled = true }
