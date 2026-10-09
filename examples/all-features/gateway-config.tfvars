entra_auth = { enabled = true } # JWTs from the stacks/identity app (looked up by name)

features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  azure_ai_search       = true
  document_intelligence = true
  embeddings_backend    = true # semantic cache
  mcp_sample            = true
  api_center_onboarding = true
}

# Existing AI Search services registered as APIM backends.
ai_search_instances = [
  { name = "search-products", endpoint = "https://<search-service>.search.windows.net" },
]

# The embeddings deployment of platform.tfvars (account endpoint from `task output STACK=platform NAME=foundry_endpoints`).
embeddings_backend_url = "https://<foundry-account>.openai.azure.com/openai/deployments/text-embedding-3-large"

# Application Insights / Azure Monitor diagnostics on the service APIs.
api_diagnostics = { enabled = true, body_bytes = 1024 }
