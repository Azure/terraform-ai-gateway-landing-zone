# Backends deployed: one per Foundry account of stacks/platform (derived), then the
# llm_backends below. foundry_backends.enabled = false would deploy only llm_backends.
inference_api_type = "OpenAIV1"

# Circuit breaker of the Foundry-derived backends (every property is optional; these are
# the defaults except failure_count). Each backend below can set its own.
foundry_backends = {
  circuit_breaker = {
    failure_count = 5 # failures within failure_interval that trip the breaker (default 3)
  }
}

features = {
  unified_ai_api        = true # the single /models-style endpoint over every backend
  api_center_onboarding = true
}

# Credentials for aws-bedrock backends with auth_type = "aws-sigv4": versionless
# Key Vault secret URIs (APIM resolves them with its managed identity).
aws = {
  region                = "us-east-1"
  access_key_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/aws-access-key"
  secret_key_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/aws-secret-key"
}

llm_backends = [
  # Azure OpenAI resource outside Foundry, called with the APIM managed identity.
  {
    backend_id   = "aoai-legacy-westeurope"
    backend_type = "azure-openai"
    endpoint     = "https://<aoai-resource>.openai.azure.com/"
    auth_scheme  = "managedIdentity"
    auth_type    = "managed-identity"
    supported_models = [
      { name = "gpt-5.4-mini", sku = "GlobalStandard", capacity = 50, modelVersion = "2026-03-17" },
    ]
    priority = 2 # lower priority than the Foundry backends: used when they fail
    weight   = 50
    # Trip faster and recover sooner than the defaults (3 failures / PT5M, out for PT1M).
    circuit_breaker = {
      failure_count    = 2
      failure_interval = "PT1M"
      trip_duration    = "PT30S"
    }
  },
  # Third-party OpenAI-compatible endpoint with a bearer key from Key Vault. APIM sends the
  # named value as the Authorization header as it is: the secret holds "Bearer <key>".
  {
    backend_id   = "partner-openai-compatible"
    backend_type = "external"
    endpoint     = "https://api.partner.example.com"
    auth_scheme  = "apiKey"
    auth_type    = "api-key-bearer"
    auth_config = {
      named_value_key      = "partner-api-key"
      key_vault_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/partner-api-key"
    }
    supported_models = [
      { name = "partner-large", sku = "OnDemand", capacity = 1, modelFormat = "Partner" },
    ]
    # Count every 5xx and 429 as a failure and honour the partner's own Retry-After.
    circuit_breaker = {
      status_code_ranges = [{ min = 429, max = 429 }, { min = 500, max = 599 }]
      accept_retry_after = true
    }
  },
  # AWS Bedrock, signed in the APIM policy with the aws.* credentials above.
  {
    backend_id   = "bedrock-us-east-1"
    backend_type = "aws-bedrock"
    endpoint     = "https://bedrock-runtime.us-east-1.amazonaws.com"
    auth_type    = "aws-sigv4"
    supported_models = [
      { name = "anthropic.claude-sonnet", sku = "OnDemand", capacity = 1, modelFormat = "Anthropic" },
    ]
    circuit_breaker = { enabled = false } # no circuit breaker on this backend
  },
]

model_aliases = [
  # Try the Foundry deployments first, then the Azure OpenAI fallback.
  { name = "fast", models = ["gpt-5.4-mini"], strategy = "priority" },
  # Split traffic 80/20 between two models.
  { name = "balanced", models = ["gpt-5.4", "gpt-5.4-mini"], strategy = "weighted", weights = [80, 20] },
]
