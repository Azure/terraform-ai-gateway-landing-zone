# =============================================================================
# MODULE: Security
# Key Vault + RBAC Role Assignments for Managed Identity
# =============================================================================

# -----------------------------------------------------------------------------
# KEY VAULT
# -----------------------------------------------------------------------------

resource "azurerm_key_vault" "citadel" {
  name                            = var.key_vault_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  tenant_id                       = var.tenant_id
  sku_name                        = var.key_vault_sku
  soft_delete_retention_days      = var.soft_delete_retention_days
  purge_protection_enabled        = var.purge_protection_enabled
  rbac_authorization_enabled      = var.rbac_authorization_enabled
  enabled_for_template_deployment = true
  public_network_access_enabled   = var.public_network_access_enabled
  tags                            = var.tags

  network_acls {
    default_action = var.network_acl_default_action
    bypass         = "AzureServices"
    ip_rules       = var.ip_rules
  }
}

# -----------------------------------------------------------------------------
# RBAC: Deployer gets Key Vault Administrator
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "deployer_kv_admin" {
  scope                = azurerm_key_vault.citadel.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.deployer_object_id
}

# -----------------------------------------------------------------------------
# RBAC: Managed Identity gets Key Vault Secrets User (for APIM/Logic App)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "uami_kv_secrets_user" {
  scope                = azurerm_key_vault.citadel.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.managed_identity_principal_id
}

# -----------------------------------------------------------------------------
# RBAC: Grant each AI Foundry system-assigned MI "Key Vault Secrets User"
# Bicep parity: keyvault-rbac.bicep — loops over aiFoundryPrincipalIds.
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "foundry_kv_secrets_user" {
  # Use foundry_principal_count (derived from var.ai_foundry_instances length
  # in the root module) because var.foundry_principal_ids comes from a module
  # output and isn't known at plan time — Terraform forbids unknown values in
  # `count`.
  count                = var.foundry_principal_count
  scope                = azurerm_key_vault.citadel.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.foundry_principal_ids[count.index]
}

# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT FOR KEY VAULT
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${var.key_vault_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.citadel.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id_key_vault != "" ? [1] : []
    content {
      name                 = "kv-dns-group"
      private_dns_zone_ids = [var.dns_zone_id_key_vault]
    }
  }
}

# -----------------------------------------------------------------------------
# Wait for Key Vault Administrator RBAC assignment to propagate before
# attempting data-plane operations (secret writes). Azure AD RBAC propagation
# can take 30-60 seconds.
# -----------------------------------------------------------------------------

resource "time_sleep" "wait_for_kv_rbac" {
  depends_on      = [azurerm_role_assignment.deployer_kv_admin]
  create_duration = "60s"
}

# -----------------------------------------------------------------------------
# Wait for Key Vault network ACL changes (ip_rules) to propagate before
# attempting data-plane operations. KV firewall updates typically take
# 30-60s to take effect, and calls made in that window fail with
# 403 ForbiddenByConnection even when the caller IP IS in the allowlist.
# The trigger forces a new sleep whenever ip_rules changes.
# -----------------------------------------------------------------------------

resource "time_sleep" "wait_for_kv_acl" {
  depends_on      = [azurerm_key_vault.citadel]
  create_duration = "90s"

  triggers = {
    ip_rules       = join(",", sort(var.ip_rules))
    default_action = var.network_acl_default_action
  }
}

# -----------------------------------------------------------------------------
# STORE APIM GATEWAY KEY IN KEY VAULT (placeholder — disabled by default)
# -----------------------------------------------------------------------------
# Gated behind `var.create_apim_gateway_key_secret`. Nothing in the Terraform
# stack reads this secret programmatically; only notebook samples reference
# it, and they fetch the real key out-of-band via the Azure CLI. Enabling
# this requires KV data-plane access from the deployer IP, which is the
# primary source of 403 ForbiddenByFirewall errors on apply.
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "apim_subscription_key" {
  count        = var.create_apim_gateway_key_secret ? 1 : 0
  name         = "apim-gateway-key"
  value        = "PLACEHOLDER-update-after-apim-deploy"
  key_vault_id = azurerm_key_vault.citadel.id
  tags         = var.tags

  depends_on = [
    azurerm_role_assignment.deployer_kv_admin,
    time_sleep.wait_for_kv_rbac,
    time_sleep.wait_for_kv_acl,
  ]
}
