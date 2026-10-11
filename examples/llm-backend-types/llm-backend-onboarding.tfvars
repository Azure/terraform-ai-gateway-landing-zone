# Every kind of LLM backend behind one gateway:
#
#   Foundry                       derived from stacks/platform (nothing listed below)
#   External, OpenAI-compatible   a third-party endpoint, bearer key
#   Google Gemini                 gemini-openai, bearer key
#   AWS Bedrock Mantle            aws-bedrock-mantle, OpenAI-compatible, bearer key
#   AWS Bedrock                   aws-bedrock, native Converse API, AWS SigV4
#
# Credentials are Key Vault secret references (versionless URIs, read by the APIM identity,
# which needs Key Vault Secrets User): no secret value is in Terraform. Create the secrets
# first (see README.md), then `task apply STACK=llm-backend-onboarding`.
inference_api_type = "OpenAIV1"

features = {
  # Gemini and Bedrock are reached through the Unified AI API (/unified-ai), which builds
  # the provider-specific path of each backend type.
  unified_ai_api = true
}

# 1. Foundry: one backend per Foundry account of platform.tfvars, serving its deployments
# (gpt-5.4-mini). Managed identity, nothing to configure. Only the circuit breaker can be tuned:
# foundry_backends = { circuit_breaker = { failure_count = 5 } }

# AWS SigV4 credentials of the aws-bedrock backend (the access key id and the secret key,
# as they are). The Mantle backend uses its own bearer key below.
aws = {
  region                = "us-east-1"
  access_key_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/aws-access-key"
  secret_key_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/aws-secret-key"
}

llm_backends = [
  # 2. External OpenAI-compatible provider. The endpoint includes the API root (/v1): the
  # Universal LLM API appends /chat/completions to it. api-key-bearer: the Key Vault secret
  # holds the complete header value, "Bearer <key>".
  {
    backend_id   = "partner-openai-compatible"
    backend_type = "external"
    endpoint     = "https://api.partner.example.com/v1"
    auth_type    = "api-key-bearer"
    auth_config = {
      named_value_key      = "partner-api-key"
      key_vault_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/partner-api-key"
    }
    supported_models = [
      { name = "partner-large", sku = "OnDemand", capacity = 1, modelFormat = "Partner" },
    ]
    # A partner API with strict rate limits: back off for longer.
    circuit_breaker = {
      trip_duration = "PT5M"
    }
  },

  # 3. Google Gemini through its OpenAI-compatible API (the gateway appends
  # /v1beta/openai/chat/completions). A bearer key from Google AI Studio; the secret
  # holds "Bearer <key>".
  {
    backend_id   = "gemini-openai"
    backend_type = "gemini-openai"
    endpoint     = "https://generativelanguage.googleapis.com"
    auth_type    = "api-key-bearer" # the default of this backend type, shown for clarity
    auth_config = {
      named_value_key      = "gemini-api-key"
      key_vault_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/gemini-api-key"
    }
    supported_models = [
      { name = "gemini-2.5-flash", sku = "OnDemand", capacity = 1, modelFormat = "Google", modelVersion = "1" },
    ]
  },

  # 4. AWS Bedrock Mantle: OpenAI-compatible endpoint of Bedrock, with a Bedrock API key
  # as bearer (the secret holds "Bearer <key>").
  {
    backend_id   = "bedrock-mantle-us-east-1"
    backend_type = "aws-bedrock-mantle"
    endpoint     = "https://bedrock-mantle.us-east-1.api.aws"
    auth_type    = "api-key-bearer" # the default of this backend type
    auth_config = {
      named_value_key      = "bedrock-mantle-api-key"
      key_vault_secret_uri = "https://<key-vault-name>.vault.azure.net/secrets/bedrock-mantle-api-key"
    }
    supported_models = [
      { name = "openai.gpt-oss-120b", sku = "OnDemand", capacity = 1, modelFormat = "OpenAI", modelVersion = "1" },
    ]
  },

  # 5. AWS Bedrock, native Converse API, signed with AWS SigV4 in the gateway policy using
  # the aws.* credentials above (no auth_config).
  {
    backend_id   = "bedrock-us-east-1"
    backend_type = "aws-bedrock"
    endpoint     = "https://bedrock-runtime.us-east-1.amazonaws.com"
    auth_type    = "aws-sigv4" # the default of this backend type
    supported_models = [
      { name = "us.anthropic.claude-3-5-haiku-20241022-v1:0", sku = "OnDemand", capacity = 1, modelFormat = "Anthropic", modelVersion = "1" },
    ]
    circuit_breaker = { enabled = false } # no circuit breaker on this backend
  },
]

model_aliases = [
  # The same OpenAI-style request, three clouds: Foundry first, then Bedrock Mantle, then
  # Gemini when the previous one fails (Unified AI API, /unified-ai/v1/chat/completions).
  { name = "multi-cloud", models = ["gpt-5.4-mini", "openai.gpt-oss-120b", "gemini-2.5-flash"], strategy = "priority" },
]
