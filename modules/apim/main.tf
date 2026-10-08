# =============================================================================
# MODULE: API Management
# Unified AI Gateway — core of the Citadel Governance Hub
# Mirrors bicep/infra/modules/apim.bicep
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

# APIM service (Azure Verified Module). Child objects (APIs, products, named
# values, loggers, policies) stay in this module and the gateway modules.
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
  min_api_version     = local.is_apim_v2 ? "2024-05-01" : "2021-08-01"

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
# PRIVATE ENDPOINT (for APIM V2 SKUs)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# APIM public network access — set AFTER activation.
# Azure rejects CreateOrUpdate with publicNetworkAccess=Disabled on initial
# activation (error: ActivateServiceWithPrivateEndpointAccessNotAllowed).
# This azapi PATCH runs once the service is active and applies the desired
# setting (V2 SKUs only; classic SKUs always keep public access enabled).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# NAMED VALUES (configuration pushed into APIM policies)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_named_value" "uami_client_id" {
  name                = "uami-client-id"
  display_name        = "uami-client-id"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.managed_identity_client_id
  secret              = false
}

resource "azurerm_api_management_named_value" "pii_service_url" {
  count               = var.enable_pii_redaction ? 1 : 0
  name                = "piiServiceUrl"
  display_name        = "piiServiceUrl"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.pii_service_endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "content_safety_url" {
  count               = var.enable_content_safety ? 1 : 0
  name                = "contentSafetyServiceUrl"
  display_name        = "contentSafetyServiceUrl"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.content_safety_endpoint
  secret              = false
}

# NOTE: APIM validates <validate-jwt> <openid-config url="..."/> at fragment
# create time even when wrapped in <choose><when>. The URL must resolve to a
# reachable OIDC metadata document, so when Entra auth is disabled we fall
# back to the Microsoft 'common' tenant (always reachable). Runtime gate is
# still enforced by the `entra-auth` flag in frag-aad-auth.xml.

resource "azurerm_api_management_named_value" "entra_tenant_id" {
  name                = "tenant-id"
  display_name        = "tenant-id"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_tenant_id != "" ? var.entra_tenant_id : "common"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_client_id" {
  name                = "client-id"
  display_name        = "client-id"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_client_id != "" ? var.entra_client_id : "00000000-0000-0000-0000-000000000000"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_audience" {
  name                = "audience"
  display_name        = "audience"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_audience != "" ? var.entra_audience : "api://disabled"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_auth_flag" {
  name                = "entra-auth"
  display_name        = "entra-auth"
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
  value               = tostring(var.entra_auth_enabled)
  secret              = false
}

# APIs (Universal LLM, Azure OpenAI, Unified AI, service APIs, MCP servers) are
# published by modules/gateway-api from the root apis.tf.

# -----------------------------------------------------------------------------
# PRODUCTS (use-case access contracts)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_product" "default_contract" {
  product_id            = "default-ai-access"
  display_name          = "Default AI Access Contract"
  description           = "Default governed access to all LLM backends"
  api_management_name   = local.apim.name
  resource_group_name   = var.resource_group_name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "universal_llm_default" {
  api_name            = var.default_product_api_names.universal_llm
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_api" "openai_default" {
  api_name            = var.default_product_api_names.azure_openai
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = local.apim.name
  resource_group_name = var.resource_group_name
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
