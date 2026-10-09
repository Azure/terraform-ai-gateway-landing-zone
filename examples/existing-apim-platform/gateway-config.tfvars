# Gateway configuration on an existing APIM. The Foundry-derived features need
# the platform's naming contract, so they're off; the Entra values are given
# explicitly because there is no identity stack.
entra_auth = {
  enabled   = true
  tenant_id = "<tenant-id>"
  client_id = "<client-id>"
  audience  = "api://<client-id>"
}
features = {
  pii_redaction         = false
  pii_anonymization     = false
  content_safety        = false
  document_intelligence = false
  mcp_sample            = false
  api_center_onboarding = false
}
