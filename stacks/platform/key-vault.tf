# Key Vault (RBAC). The deployer (apply identity in CI) is Key Vault
# Administrator; access contracts write their secrets here.
module "security" {
  source = "../../modules/security"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry

  key_vault_name     = local.names.key_vault
  key_vault_sku      = var.key_vault.sku
  tenant_id          = data.azurerm_client_config.current.tenant_id
  deployer_object_id = data.azurerm_client_config.current.object_id

  managed_identity_principal_id = module.identity["apim"].principal_id
  foundry_principal_ids         = flatten(module.foundry[*].foundry_principal_ids)
  foundry_principal_count       = length(local.foundry_instances)
  secret_writer_principal_ids   = var.secret_writer_principal_ids
  secret_reader_principal_ids   = var.secret_reader_principal_ids

  subnet_id                        = local.network.subnet_ids.pe
  dns_zone_id_key_vault            = lookup(local.zone_ids, "key_vault", "")
  dns_zone_group_managed_by_policy = local.network.dns_zone_groups_managed_by_policy

  soft_delete_retention_days = var.key_vault.soft_delete_retention_days
  purge_protection_enabled   = var.key_vault.purge_protection_enabled
  rbac_authorization_enabled = true

  # dev_access needs public access "from selected networks" (Azure ignores
  # ip_rules when public access is disabled); the default action stays Deny.
  public_network_access_enabled = length(local.dev_cidrs) > 0 || var.key_vault.public_network_access_enabled
  network_acl_default_action    = var.key_vault.network_acl_default_action
  ip_rules                      = local.dev_cidrs
}
