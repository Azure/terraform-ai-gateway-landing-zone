# Entra ID as the gateway's JWT identity provider: fills the JWT-OpenIdConfigUrl, JWT-Issuer and
# JWT-AppRegistrationId named values from the stacks/identity app (found by name: needs Graph
# Application.Read.All). Without Graph rights, set the values scripts/entra_id_setup.py prints:
#   entra_auth = { enabled = true, tenant_id = "<tenant-id>", client_id = "<gateway-app-client-id>", audience = "api://<gateway-app-client-id>" }
# Every API still requires the subscription key: contracts add the JWT with jwt_required.
entra_auth = { enabled = true }

features = {
  pii_redaction         = true
  pii_anonymization     = true
  content_safety        = true
  document_intelligence = false
  mcp_sample            = false
  api_center_onboarding = false
}
