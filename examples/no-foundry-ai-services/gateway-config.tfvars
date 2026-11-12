# Model-agnostic gateway configuration (named values, shared fragments, service APIs).
entra_auth = { enabled = false }
features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  document_intelligence = false
  mcp_sample            = false
  api_center_onboarding = true
}

# Where PII redaction and content safety call: the standalone accounts of stacks/platform.
# source = "url" (with url = "https://<name>.cognitiveservices.azure.com/") uses existing services.
pii_service            = { source = "dedicated" }
content_safety_service = { source = "dedicated" }
