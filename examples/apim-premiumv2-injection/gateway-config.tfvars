# Model-agnostic gateway configuration (named values, shared fragments, service APIs).
entra_auth = { enabled = false } # true: JWTs from the stacks/identity app (looked up by name)
features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  document_intelligence = false
  mcp_sample            = false
  api_center_onboarding = false
}
