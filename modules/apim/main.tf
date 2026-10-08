# =============================================================================
# MODULE: API Management
# Unified AI Gateway — core of the Citadel Governance Hub
# Mirrors bicep/infra/modules/apim.bicep
# =============================================================================

# -----------------------------------------------------------------------------
# STATE MIGRATION: `azapi_resource.azure_monitor_logger` → `terraform_data.*`
# The logger used to be managed with azapi_resource, but that resource aborts
# with "already exists" whenever the logger is present in Azure but missing
# from state. We replaced it with a terraform_data + `az rest PUT` (idempotent
# PUT). The `removed` block below drops the old azapi entry from state on the
# next plan without deleting the actual Azure logger — a fresh apply then
# upserts it through the new terraform_data resource.
# -----------------------------------------------------------------------------
removed {
  from = azapi_resource.azure_monitor_logger
  lifecycle {
    destroy = false
  }
}

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

  is_vnet_injection = var.apim_network_type != "None" && !var.is_apim_v2
  is_internal       = var.apim_network_type == "Internal"

  # Bicep parity: V2 SKUs always use outbound VNet integration
  # (virtualNetworkType = External + subnet delegated to Microsoft.Web/serverFarms).
  # Inbound stays public / private endpoint; apim_network_type is ignored for V2.
  is_vnet_integration  = var.is_apim_v2
  virtual_network_type = local.is_vnet_injection ? var.apim_network_type : (local.is_vnet_integration ? "External" : "None")
}

resource "azurerm_api_management" "citadel" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = local.apim_sku_string
  tags                = var.tags

  # Bicep parity: `minApiVersion` — control plane API floor.
  # V2 SKUs use 2024-05-01 floor; others use 2021-08-01.
  min_api_version = var.is_apim_v2 ? "2024-05-01" : "2021-08-01"

  # Bicep parity: availability zones (Premium + skuCount>1; []/null otherwise).
  zones = length(var.apim_zones) > 0 ? var.apim_zones : null

  # Bicep parity: publicNetworkAccess gated for V2 SKUs only.
  # Azure rejects APIM creation with publicNetworkAccess=Disabled
  # ("ActivateServiceWithPrivateEndpointAccessNotAllowed"), so we always
  # create with public access enabled and then flip it off (if requested)
  # via `azapi_update_resource.apim_disable_public_access` below.
  public_network_access_enabled = true

  lifecycle {
    ignore_changes = [public_network_access_enabled]

    # SKU x network matrix (review 7.5.4.1) and scale rules.
    precondition {
      condition     = contains(["Developer", "Premium", "StandardV2", "PremiumV2"], var.sku_name)
      error_message = "APIM sku must be Developer, Premium, StandardV2 or PremiumV2."
    }
    precondition {
      condition     = var.is_apim_v2 == contains(["StandardV2", "PremiumV2"], var.sku_name)
      error_message = "is_apim_v2 must be true exactly for StandardV2/PremiumV2."
    }
    precondition {
      condition     = var.is_apim_v2 || var.apim_network_type == "None" || var.apim_subnet_id != ""
      error_message = "Classic VNet injection (External/Internal) needs apim_subnet_id."
    }
    precondition {
      condition     = !var.is_apim_v2 || var.apim_v2_public_network_access || var.apim_v2_use_private_endpoint
      error_message = "Disabling public network access on a v2 SKU requires the private endpoint (apim.private_endpoint = true); otherwise the gateway is unreachable."
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

  # Bicep parity: UserAssigned only (system-assigned identity dropped upstream;
  # all backend auth + RBAC uses the user-assigned MI).
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # VNet injection for Developer/Premium SKUs; outbound VNet integration for V2 SKUs.
  dynamic "virtual_network_configuration" {
    for_each = local.is_vnet_injection || local.is_vnet_integration ? [1] : []
    content {
      subnet_id = var.apim_subnet_id
    }
  }

  virtual_network_type = local.virtual_network_type

  # Bicep parity: customProperties — TLS/cipher hardening.
  # Disable TLS 1.0 / 1.1 / SSL 3.0 on both frontend and backend.
  # Disable weak ciphers (3DES, legacy RSA/CBC suites) on the frontend.
  # Skipped for Consumption SKU (customProperties unsupported there).
  dynamic "security" {
    for_each = var.sku_name == "Consumption" ? [] : [1]
    content {
      backend_ssl30_enabled  = false
      backend_tls10_enabled  = false
      backend_tls11_enabled  = false
      frontend_ssl30_enabled = false
      frontend_tls10_enabled = false
      frontend_tls11_enabled = false

      tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled = false
      tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled = false
      tls_rsa_with_aes128_cbc_sha256_ciphers_enabled    = false
      tls_rsa_with_aes128_cbc_sha_ciphers_enabled       = false
      tls_rsa_with_aes128_gcm_sha256_ciphers_enabled    = false
      tls_rsa_with_aes256_cbc_sha256_ciphers_enabled    = false
      tls_rsa_with_aes256_cbc_sha_ciphers_enabled       = false
      triple_des_ciphers_enabled                        = false
    }
  }
}


# -----------------------------------------------------------------------------
# PRIVATE ENDPOINT (for APIM V2 SKUs)
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "apim" {
  count               = var.is_apim_v2 && var.apim_v2_use_private_endpoint ? 1 : 0
  name                = "pe-${var.apim_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.apim_name}"
    private_connection_resource_id = azurerm_api_management.citadel.id
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

# -----------------------------------------------------------------------------
# APIM public network access — set AFTER activation.
# Azure rejects CreateOrUpdate with publicNetworkAccess=Disabled on initial
# activation (error: ActivateServiceWithPrivateEndpointAccessNotAllowed).
# This azapi PATCH runs once the service is active and applies the desired
# setting (V2 SKUs only; classic SKUs always keep public access enabled).
# -----------------------------------------------------------------------------

resource "azapi_update_resource" "apim_public_network_access" {
  count       = var.is_apim_v2 ? 1 : 0
  type        = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id = azurerm_api_management.citadel.id

  body = {
    properties = {
      publicNetworkAccess = var.apim_v2_public_network_access ? "Enabled" : "Disabled"
    }
  }

  # Azure requires at least one approved private endpoint connection before
  # publicNetworkAccess can be set to Disabled (error:
  # DisablingPublicNetworkAccessRequiredPrivateEndpoint). Gate on the PE.
  depends_on = [azurerm_private_endpoint.apim]
}

# -----------------------------------------------------------------------------
# NAMED VALUES (configuration pushed into APIM policies)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_named_value" "uami_client_id" {
  name                = "uami-client-id"
  display_name        = "uami-client-id"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.managed_identity_client_id
  secret              = false
}

resource "azurerm_api_management_named_value" "pii_service_url" {
  count               = var.enable_pii_redaction ? 1 : 0
  name                = "piiServiceUrl"
  display_name        = "piiServiceUrl"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.pii_service_endpoint
  secret              = false
}

resource "azurerm_api_management_named_value" "content_safety_url" {
  count               = var.enable_content_safety ? 1 : 0
  name                = "contentSafetyServiceUrl"
  display_name        = "contentSafetyServiceUrl"
  api_management_name = azurerm_api_management.citadel.name
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
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_tenant_id != "" ? var.entra_tenant_id : "common"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_client_id" {
  name                = "client-id"
  display_name        = "client-id"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_client_id != "" ? var.entra_client_id : "00000000-0000-0000-0000-000000000000"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_audience" {
  name                = "audience"
  display_name        = "audience"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  value               = var.entra_auth_enabled && var.entra_audience != "" ? var.entra_audience : "api://disabled"
  secret              = false
}

resource "azurerm_api_management_named_value" "entra_auth_flag" {
  name                = "entra-auth"
  display_name        = "entra-auth"
  api_management_name = azurerm_api_management.citadel.name
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
  api_management_name   = azurerm_api_management.citadel.name
  resource_group_name   = var.resource_group_name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "universal_llm_default" {
  api_name            = var.default_product_api_names.universal_llm
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_api" "openai_default" {
  api_name            = var.default_product_api_names.azure_openai
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = azurerm_api_management.citadel.name
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
  api_management_id = azurerm_api_management.citadel.id
  connection_string = var.redis_cache_connection_string
  description       = "Azure Managed Redis for APIM semantic cache"
}
