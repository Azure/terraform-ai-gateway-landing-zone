# No Foundry accounts from this repository: every backend is declared here.
foundry_backends = { enabled = false }

inference_api_type = "OpenAIV1"
features           = { api_center_onboarding = false }

extra_llm_backends = [
  # Existing Foundry / Azure OpenAI accounts; the existing APIM identity needs
  # Cognitive Services User (Foundry) or Cognitive Services OpenAI User on them.
  {
    backend_id   = "aif-existing-primary"
    backend_type = "ai-foundry"
    endpoint     = "https://<foundry-account>.cognitiveservices.azure.com/"
    auth_scheme  = "managedIdentity"
    auth_type    = "managed-identity"
    supported_models = [
      { name = "gpt-5.4-mini", sku = "GlobalStandard", capacity = 100, modelVersion = "2026-03-17" },
    ]
  },
]

model_aliases = [
  { name = "fast", models = ["gpt-5.4-mini"], strategy = "priority" },
]
