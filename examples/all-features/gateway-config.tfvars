entra_auth = { enabled = true } # JWTs from the stacks/identity app (looked up by name)

features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  azure_ai_search       = true
  document_intelligence = true
  mcp_sample            = true
  api_center_onboarding = true
}

# Existing AI Search services registered as APIM backends.
ai_search_instances = [
  { name = "search-products", endpoint = "https://<search-service>.search.windows.net" },
]

# Semantic cache (Redis from platform features.semantic_cache) with the embeddings deployment of
# platform.tfvars on the primary Foundry account. Contracts opt in with services[*].semantic_cache.
semantic_cache = {
  enabled               = true
  embeddings_deployment = "text-embedding-3-large"
  score_threshold       = 0.05
  ttl_seconds           = 300
}

# Application Insights / Azure Monitor diagnostics on the service APIs.
api_diagnostics = { enabled = true, body_bytes = 1024 }
