# =============================================================================
# MODULE: API Management service (platform stack)
# The service, its network model, private endpoint, internal DNS and the
# external (Redis) cache. Mirrors bicep/infra/modules/apim.bicep.
# =============================================================================

# -----------------------------------------------------------------------------
# API MANAGEMENT SERVICE
# -----------------------------------------------------------------------------

locals {
  # Map SKU names to the format Terraform expects
  sku_name_map = {
    "Developer"  = "Developer_1"
    "StandardV2" = "StandardV2_1"
    "Premium"    = "Premium_1"
    "PremiumV2"  = "PremiumV2_1"
  }

  apim_sku_string = var.sku_capacity > 1 ? replace(
    local.sku_name_map[var.sku_name], "_1", "_${var.sku_capacity}"
  ) : local.sku_name_map[var.sku_name]

  is_apim_v2 = contains(["StandardV2", "PremiumV2"], var.sku_name)

  # vnet_mode -> ARM virtualNetworkType (review 7.5.4.1):
  #   external / internal  classic VNet injection (Developer, Premium)
  #   integration          v2 outbound VNet integration (External + serverFarms subnet)
  #   injection            Premium v2 VNet injection (Internal + hostingEnvironments subnet)
  virtual_network_type = { none = "None", external = "External", internal = "Internal", integration = "External", injection = "Internal" }[var.vnet_mode]
  uses_subnet          = var.vnet_mode != "none"
  private_vip          = contains(["internal", "injection"], var.vnet_mode)
  # Inbound private endpoint: v2 SKUs without injection.
  use_private_endpoint = local.is_apim_v2 && var.apim_v2_use_private_endpoint && contains(["none", "integration"], var.vnet_mode)
}

# APIM service (Azure Verified Module). Child objects belong to other stacks
# (review 7.8): named values, fragments, backends and APIs to gateway-config
# and llm-backend-onboarding, products and subscriptions to access-contracts.
module "service" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.9.0"

  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = local.apim_sku_string
  tags                = var.tags
  enable_telemetry    = var.enable_telemetry
  # v2 SKUs ignore apiVersionConstraint (always read back empty).
  min_api_version = local.is_apim_v2 ? null : "2021-08-01"

  # Bicep parity: availability zones (Premium + skuCount>1; []/null otherwise).
  zones = length(var.apim_zones) > 0 ? var.apim_zones : null

  # Azure rejects creating a service with public access disabled
  # (ActivateServiceWithPrivateEndpointAccessNotAllowed) and requires an
  # approved private endpoint first: the first apply creates it public, the next
  # apply (service + PE exist) applies the requested setting. Classic SKUs
  # always keep public access.
  public_network_access_enabled = !local.is_apim_v2 || !local.apim_exists || var.apim_v2_public_network_access

  # Bicep parity: UserAssigned only.
  managed_identities = { user_assigned_resource_ids = [var.managed_identity_id] }

  virtual_network_type      = local.virtual_network_type
  virtual_network_subnet_id = local.uses_subnet && var.apim_subnet_id != "" ? var.apim_subnet_id : null
  # Classic external/internal only: Standard-SKU public IP for the service (stv2).
  public_ip_address_id = var.public_ip_address_id

  # Legacy protocols and weak ciphers off (Bicep parity).
  security = {}

  private_endpoints_manage_dns_zone_group = !var.dns_zone_group_managed_by_policy
  private_endpoints = local.use_private_endpoint ? {
    gateway = {
      name                            = "pe-${var.apim_name}"
      private_service_connection_name = "psc-${var.apim_name}"
      subnet_resource_id              = var.pe_subnet_id
      private_dns_zone_group_name     = "apim-dns-group"
      private_dns_zone_resource_ids   = var.dns_zone_id_apim != "" && !var.dns_zone_group_managed_by_policy ? [var.dns_zone_id_apim] : []
      tags                            = var.tags
    }
  } : {}
}

# Plan-time rules for the SKU x network matrix (review 7.5.4.1) and scale.
resource "terraform_data" "service_rules" {
  input = var.apim_name

  lifecycle {
    precondition {
      condition     = contains(["Developer", "Premium", "StandardV2", "PremiumV2"], var.sku_name)
      error_message = "APIM sku must be Developer, Premium, StandardV2 or PremiumV2."
    }
    precondition {
      condition = contains(lookup({
        Developer  = ["none", "external", "internal"]
        Premium    = ["none", "external", "internal"]
        StandardV2 = ["none", "integration"]
        PremiumV2  = ["none", "integration", "injection"]
      }, var.sku_name, []), var.vnet_mode)
      error_message = "vnet_mode ${var.vnet_mode} isn't supported on ${var.sku_name} (Developer/Premium: none, external, internal; StandardV2: none, integration; PremiumV2: none, integration, injection)."
    }
    precondition {
      condition     = !local.uses_subnet || var.apim_subnet_id != ""
      error_message = "vnet_mode ${var.vnet_mode} needs apim_subnet_id."
    }
    precondition {
      condition     = !local.is_apim_v2 || var.apim_v2_public_network_access || local.use_private_endpoint || var.vnet_mode == "injection"
      error_message = "Disabling public network access on a v2 SKU requires the private endpoint (apim.private_endpoint = true, vnet_mode none or integration); otherwise the gateway is unreachable."
    }
    precondition {
      condition     = var.public_ip_address_id == null || contains(["external", "internal"], var.vnet_mode)
      error_message = "public_ip_address_id applies only to classic external/internal injection."
    }
    precondition {
      condition     = var.sku_name != "Developer" || var.sku_capacity == 1
      error_message = "The Developer SKU can't scale out: apim.capacity must be 1."
    }
    precondition {
      condition     = length(var.apim_zones) == 0 || (var.sku_name == "Premium" && var.sku_capacity >= length(var.apim_zones))
      error_message = "Availability zones need the Premium SKU and at least one unit per zone (capacity >= number of zones)."
    }
  }
}

locals {
  apim = {
    id                   = module.service.resource_id
    name                 = module.service.name
    gateway_url          = module.service.apim_gateway_url
    portal_url           = module.service.portal_url
    management_api_url   = module.service.apim_management_url
    private_ip_addresses = module.service.private_ip_addresses
  }
}

# Whether the service already exists (drives the public-access flip above).
data "azapi_resource" "service_state" {
  type             = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id      = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
  ignore_not_found = true
}

locals {
  apim_exists = data.azapi_resource.service_state.exists
}

# -----------------------------------------------------------------------------
# APIM REDIS CACHE (Bicep parity: `service/caches` resource)
# Links Azure Managed Redis to APIM for semantic caching. Created only when
# Redis is enabled. The count uses the plan-time flag, not the connection string:
# the string is only known after Redis is created, so gating on it made a fresh
# deployment with enable_redis_cache = true fail at plan ("Invalid count argument").
# -----------------------------------------------------------------------------

resource "azurerm_api_management_redis_cache" "default" {
  count             = var.enable_redis_cache ? 1 : 0
  name              = "Default"
  api_management_id = local.apim.id
  connection_string = var.redis_cache_connection_string
  description       = "Azure Managed Redis for APIM semantic cache"
}
