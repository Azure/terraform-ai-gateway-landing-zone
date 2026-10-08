# Keyless state account: Entra ID only (backend use_azuread_auth = true),
# versioning + soft delete for recovery, one container per stack.
module "state_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  name             = local.names.state_storage_account
  location         = var.location
  parent_id        = module.state_resource_group.resource_id
  tags             = local.tags
  enable_telemetry = var.enable_telemetry

  account_kind                      = "StorageV2"
  account_sku_name                  = "Standard_${var.state_storage.replication}"
  access_tier                       = "Hot"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = var.state_storage.public_network_access_enabled

  network_rules = {
    default_action = length(var.state_storage.allowed_ip_ranges) > 0 || !var.state_storage.public_network_access_enabled ? "Deny" : "Allow"
    bypass         = toset([])
    ip_rules       = toset([for r in var.state_storage.allowed_ip_ranges : trimsuffix(r, "/32")])
  }

  blob_properties = {
    versioning_enabled = true
    delete_retention_policy = {
      enabled = true
      days    = var.state_storage.retention_days
    }
    container_delete_retention_policy = {
      enabled = true
      days    = var.state_storage.retention_days
    }
  }

  containers = { for s in var.stacks : s => { name = s } }

  private_endpoints_manage_dns_zone_group = try(var.state_storage.private_endpoint.private_dns_zone_id, null) != null
  private_endpoints = var.state_storage.private_endpoint == null ? {} : {
    blob = {
      name                            = "pe-${local.names.state_storage_account}-blob"
      private_service_connection_name = "psc-blob"
      subnet_resource_id              = var.state_storage.private_endpoint.subnet_id
      subresource_name                = "blob"
      private_dns_zone_resource_ids   = var.state_storage.private_endpoint.private_dns_zone_id == null ? [] : [var.state_storage.private_endpoint.private_dns_zone_id]
      tags                            = local.tags
    }
  }

  role_assignments = merge(
    {
      deployer = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = data.azurerm_client_config.current.object_id
      }
      apply = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = local.apply_principal_id
        principal_type             = "ServicePrincipal"
      }
    },
    # Plans run with -lock=false, so read access is enough.
    local.separate_plan_identity ? {
      plan = {
        role_definition_id_or_name = "Storage Blob Data Reader"
        principal_id               = local.plan_principal_id
        principal_type             = "ServicePrincipal"
      }
    } : {},
    { for k, id in var.state_admin_principal_ids : "admin-${k}" => {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = id
    } },
  )
}
