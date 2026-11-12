# Graph is kept off the pipeline: the Entra app values are set explicitly.
entra_auth = {
  enabled   = true
  tenant_id = "<tenant-id>"
  client_id = "<gateway-app-client-id>"
  audience  = "api://<gateway-app-client-id>"
}
features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  api_center_onboarding = true
}
