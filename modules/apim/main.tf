# =============================================================================
# MODULE: API Management service (platform stack)
# The service, its network model, private endpoint, internal DNS and the
# external (Redis) cache.
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

  # Zone-redundant v2 instances are created with azapi: ARM takes properties.zoneRedundant (API
  # 2025-03-01-preview) at creation only, and azurerm_api_management can't send it (it sends zones,
  # which ARM rejects on v2 SKUs: AvailabilityZonesNotSupportedInSku).
  v2_zone_redundant = local.is_apim_v2 && var.zone_redundant

  # Azure rejects creating a service with public access disabled
  # (ActivateServiceWithPrivateEndpointAccessNotAllowed) and requires an
  # approved private endpoint first: the first apply creates it public, the next
  # apply (service + PE exist) applies the requested setting. Classic SKUs
  # always keep public access.
  public_network_access = !local.is_apim_v2 || !local.apim_exists || var.apim_v2_public_network_access

  # Legacy protocols and weak ciphers off: the customProperties azurerm writes for `security = {}`.
  hardened_custom_properties = merge(
    { "Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2" = "False" },
    { for p in ["Ssl30", "Tls10", "Tls11"] : "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.${p}" => "false" },
    { for p in ["Ssl30", "Tls10", "Tls11"] : "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.${p}" => "false" },
    { for c in [
      "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA", "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
      "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA", "TLS_RSA_WITH_AES_128_CBC_SHA", "TLS_RSA_WITH_AES_128_CBC_SHA256",
      "TLS_RSA_WITH_AES_128_GCM_SHA256", "TLS_RSA_WITH_AES_256_CBC_SHA", "TLS_RSA_WITH_AES_256_CBC_SHA256",
      "TLS_RSA_WITH_AES_256_GCM_SHA384", "TripleDes168",
    ] : "Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.${c}" => "false" },
  )
}

# APIM service (Azure Verified Module). Child objects belong to other stacks
# (review 7.8): named values, fragments, backends and APIs to gateway-config
# and llm-backend-onboarding, products and subscriptions to access-contracts.
module "service" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.9.0"
  count   = local.v2_zone_redundant ? 0 : 1

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

  # availability zones (Premium + skuCount>1; []/null otherwise).
  zones = length(var.apim_zones) > 0 ? var.apim_zones : null

  public_network_access_enabled = local.public_network_access

  # UserAssigned only.
  # UserAssigned for everything; SystemAssigned too when the semantic cache needs it
  # (llm-semantic-cache-lookup only calls the embeddings backend as the system-assigned identity).
  managed_identities = { system_assigned = var.system_assigned_identity, user_assigned_resource_ids = [var.managed_identity_id] }

  virtual_network_type      = local.virtual_network_type
  virtual_network_subnet_id = local.uses_subnet && var.apim_subnet_id != "" ? var.apim_subnet_id : null
  # Classic external/internal only: Standard-SKU public IP for the service (stv2).
  public_ip_address_id = var.public_ip_address_id

  # Legacy protocols and weak ciphers off.
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

# Zone-redundant StandardV2 / PremiumV2 service: the same settings as the module above, plus
# zoneRedundant. Its private endpoint follows (the module creates its own).
resource "azapi_resource" "service_zone_redundant" {
  count = local.v2_zone_redundant ? 1 : 0

  type      = "Microsoft.ApiManagement/service@2025-03-01-preview"
  name      = var.apim_name
  location  = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  tags      = var.tags

  # Two blocks with literal types: azapi validates the identity type statically.
  dynamic "identity" {
    for_each = var.system_assigned_identity ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [var.managed_identity_id]
    }
  }
  dynamic "identity" {
    for_each = var.system_assigned_identity ? [] : [1]
    content {
      type         = "UserAssigned"
      identity_ids = [var.managed_identity_id]
    }
  }

  body = {
    sku = {
      name     = var.sku_name,
      capacity = var.sku_capacity
    }
    properties = {
      publisherEmail              = var.publisher_email
      publisherName               = var.publisher_name
      zoneRedundant               = true
      virtualNetworkType          = local.virtual_network_type
      virtualNetworkConfiguration = local.uses_subnet && var.apim_subnet_id != "" ? { subnetResourceId = var.apim_subnet_id } : null
      publicNetworkAccess         = local.public_network_access ? "Enabled" : "Disabled"
      customProperties            = local.hardened_custom_properties
    }
  }
  # Leaves null properties out of the request (virtualNetworkConfiguration without a subnet).
  ignore_null_property = true

  response_export_values = {
    gateway_url          = "properties.gatewayUrl"
    portal_url           = "properties.developerPortalUrl"
    management_api_url   = "properties.managementApiUrl"
    private_ip_addresses = "properties.privateIPAddresses"
  }

  timeouts {
    create = "3h"
    update = "3h"
  }
}

resource "azurerm_private_endpoint" "zone_redundant" {
  count = local.v2_zone_redundant && local.use_private_endpoint && !var.dns_zone_group_managed_by_policy ? 1 : 0

  name                = "pe-${var.apim_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.apim_name}"
    private_connection_resource_id = azapi_resource.service_zone_redundant[0].id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id_apim != "" ? [1] : []
    content {
      name                 = "apim-dns-group"
      private_dns_zone_ids = [var.dns_zone_id_apim]
    }
  }
}

# With ALZ Deploy-Private-DNS-Zones the policy owns the zone group.
resource "azurerm_private_endpoint" "zone_redundant_policy_dns" {
  count = local.v2_zone_redundant && local.use_private_endpoint && var.dns_zone_group_managed_by_policy ? 1 : 0

  name                = "pe-${var.apim_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.apim_name}"
    private_connection_resource_id = azapi_resource.service_zone_redundant[0].id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
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
    precondition {
      condition     = !var.zone_redundant || local.is_apim_v2 || (var.sku_name == "Premium" && length(var.apim_zones) > 0)
      error_message = "zone_redundant: the Developer SKU has no availability zones; classic Premium spreads its units over zones only with 2 or more units (apim.capacity >= 2)."
    }
    # ARM sets zoneRedundant of a v2 service at creation only.
    precondition {
      condition     = !local.is_apim_v2 || !local.apim_exists || local.existing_zone_redundant == local.v2_zone_redundant
      error_message = "apim.zone_redundant = ${local.v2_zone_redundant} but the existing ${var.apim_name} was created ${local.existing_zone_redundant ? "zone redundant" : "without zone redundancy"}, and Azure can't change that on StandardV2 / PremiumV2. Keep the setting, or create a new instance (another environment or naming.name_overrides.apim) and move the stacks to it: replacing ${var.apim_name} in place would drop every API, product and subscription the other stacks created."
    }
  }
}

locals {
  apim = local.v2_zone_redundant ? {
    id                   = azapi_resource.service_zone_redundant[0].id
    name                 = azapi_resource.service_zone_redundant[0].name
    gateway_url          = azapi_resource.service_zone_redundant[0].output.gateway_url
    portal_url           = try(azapi_resource.service_zone_redundant[0].output.portal_url, null)
    management_api_url   = azapi_resource.service_zone_redundant[0].output.management_api_url
    private_ip_addresses = coalesce(try(azapi_resource.service_zone_redundant[0].output.private_ip_addresses, null), [])
    system_principal_id  = try(azapi_resource.service_zone_redundant[0].identity[0].principal_id, null)
    } : {
    id                   = module.service[0].resource_id
    name                 = module.service[0].name
    gateway_url          = module.service[0].apim_gateway_url
    portal_url           = module.service[0].portal_url
    management_api_url   = module.service[0].apim_management_url
    private_ip_addresses = module.service[0].private_ip_addresses
    system_principal_id  = module.service[0].workspace_identity.principal_id
  }
}

# Whether the service already exists (drives the public-access flip above), and whether it was
# created zone redundant (v2 SKUs; the API version that returns zoneRedundant).
data "azapi_resource" "service_state" {
  type                   = "Microsoft.ApiManagement/service@2025-03-01-preview"
  resource_id            = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
  ignore_not_found       = true
  response_export_values = { zone_redundant = "properties.zoneRedundant" }
}

locals {
  apim_exists             = data.azapi_resource.service_state.exists
  existing_zone_redundant = local.apim_exists && try(data.azapi_resource.service_state.output.zone_redundant == true, false)
}

# -----------------------------------------------------------------------------
# APIM REDIS CACHE (`service/caches` resource)
# Links Azure Managed Redis to APIM (the external cache of the semantic cache). APIM
# can't use Entra auth for Azure Managed Redis, so the cache needs the connection
# string with the access key. It lives in Key Vault (written by modules/redis, never
# in state) and APIM reads it through a Key Vault-backed named value: otherwise APIM
# keeps it in a secret named value it generates ("cache-Default-connection-…").
# The count uses the plan-time flag: the secret ID is unknown on a first deployment.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_named_value" "redis_cache_connection_string" {
  count               = var.enable_redis_cache ? 1 : 0
  name                = "redis-cache-connection-string"
  display_name        = "redis-cache-connection-string"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  secret              = true

  value_from_key_vault {
    secret_id          = var.redis_cache_connection_string_secret_id
    identity_client_id = var.managed_identity_client_id
  }

  lifecycle {
    precondition {
      condition     = var.redis_cache_connection_string_secret_id != null && var.managed_identity_client_id != null
      error_message = "enable_redis_cache needs redis_cache_connection_string_secret_id (the Key Vault secret modules/redis writes) and managed_identity_client_id."
    }
  }
}

resource "azurerm_api_management_redis_cache" "default" {
  count             = var.enable_redis_cache ? 1 : 0
  name              = "Default"
  api_management_id = local.apim.id
  connection_string = "{{${azurerm_api_management_named_value.redis_cache_connection_string[0].name}}}"
  redis_cache_id    = var.redis_cache_id
  description       = "Azure Managed Redis for APIM semantic cache"
}
