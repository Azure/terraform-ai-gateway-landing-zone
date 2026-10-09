# No Foundry accounts to derive backends from: every backend is listed here.
foundry_backends = { enabled = false }

inference_api_type = "OpenAIV1"
features = {
  unified_ai_api        = false
  api_center_onboarding = true
}

extra_llm_backends = [
  # An existing Azure OpenAI resource, called with the APIM managed identity
  # (it needs Cognitive Services OpenAI User there).
  {
    backend_id   = "aoai-existing"
    backend_type = "azure-openai"
    endpoint     = "https://<aoai-resource>.openai.azure.com/"
    auth_scheme  = "managedIdentity"
    auth_type    = "managed-identity"
    supported_models = [
      { name = "gpt-4.1", sku = "GlobalStandard", capacity = 50, modelVersion = "2025-04-14" },
    ]
  },
]

model_aliases = [
  { name = "fast", models = ["gpt-4.1"], strategy = "priority" },
]
