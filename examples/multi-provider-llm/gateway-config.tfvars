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
