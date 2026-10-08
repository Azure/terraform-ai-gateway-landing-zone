# =============================================================================
# MODULE: Security
# Key Vault + RBAC Role Assignments for Managed Identity
# =============================================================================

# -----------------------------------------------------------------------------
# KEY VAULT (Azure Verified Module) — vault, RBAC and private endpoint.
# Role assignments:
#   deployer_kv_admin           deployer gets Key Vault Administrator
#   uami_kv_secrets_user        APIM/Logic App identity gets Key Vault Secrets User
#   foundry_kv_secrets_user_<n> each AI Foundry system-assigned identity gets
#                               Key Vault Secrets User (Bicep keyvault-rbac.bicep).
#   secret_writer_<k> / secret_reader_<k>
#                               pipeline identities: Secrets Officer / Secrets User.
#                               Keys use foundry_principal_count because the IDs
#                               come from a module output, unknown at plan time.
# -----------------------------------------------------------------------------

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                            = var.key_vault_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  tenant_id                       = var.tenant_id
  sku_name                        = var.key_vault_sku
  soft_delete_retention_days      = var.soft_delete_retention_days
  purge_protection_enabled        = var.purge_protection_enabled
  legacy_access_policies_enabled  = !var.rbac_authorization_enabled
  enabled_for_template_deployment = true
  public_network_access_enabled   = var.public_network_access_enabled
  tags                            = var.tags
  enable_telemetry                = var.enable_telemetry

  network_acls = {
    default_action = var.network_acl_default_action
    bypass         = "AzureServices"
    ip_rules       = var.ip_rules
  }

  role_assignments = merge(
    {
      deployer_kv_admin = {
        role_definition_id_or_name = "Key Vault Administrator"
        principal_id               = var.deployer_object_id
      }
      uami_kv_secrets_user = {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = var.managed_identity_principal_id
      }
    },
    {
      for i in range(var.foundry_principal_count) : "foundry_kv_secrets_user_${i}" => {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = var.foundry_principal_ids[i]
      }
    },
    # Pipeline identities: the apply identity writes access-contract secrets,
    # the plan identity reads them during refresh.
    { for k, id in var.secret_writer_principal_ids : "secret_writer_${k}" => {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = id
    } },
    { for k, id in var.secret_reader_principal_ids : "secret_reader_${k}" => {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = id
    } },
  )

  # false when Azure Policy (ALZ Deploy-Private-DNS-Zones) owns the DNS zone group.
  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy
  private_endpoints = {
    vault = {
      name                            = "pe-${var.key_vault_name}"
      private_service_connection_name = "psc-${var.key_vault_name}"
      subnet_resource_id              = var.subnet_id
      private_dns_zone_group_name     = "kv-dns-group"
      private_dns_zone_resource_ids   = var.dns_zone_id_key_vault != "" && !var.dns_zone_group_managed_by_policy ? [var.dns_zone_id_key_vault] : []
      tags                            = var.tags
    }
  }
}

# -----------------------------------------------------------------------------
# Wait for Key Vault Administrator RBAC assignment to propagate before
# attempting data-plane operations (secret writes). Azure AD RBAC propagation
# can take 30-60 seconds.
# -----------------------------------------------------------------------------

resource "time_sleep" "wait_for_kv_rbac" {
  depends_on      = [module.key_vault]
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
  depends_on      = [module.key_vault]
  create_duration = "90s"

  triggers = {
    ip_rules       = join(",", sort(var.ip_rules))
    default_action = var.network_acl_default_action
  }
}
