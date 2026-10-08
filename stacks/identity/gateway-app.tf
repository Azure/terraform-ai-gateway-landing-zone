# The Entra app APIM validates JWTs against. gateway-config finds it by its
# deterministic display name (names.gateway_app), so nothing is copied across.
module "gateway_app" {
  source = "../../modules/gateway-entra-app"

  display_name = local.names.gateway_app
  owners       = var.owners
}
