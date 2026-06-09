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
    "Developer"   = "Developer_1"
    "StandardV2"  = "StandardV2_1"
    "Premium"     = "Premium_1"
    "PremiumV2"   = "PremiumV2_1"
  }

  apim_sku_string = var.sku_capacity > 1 ? replace(
    local.sku_name_map[var.sku_name], "_1", "_${var.sku_capacity}"
  ) : local.sku_name_map[var.sku_name]

  is_vnet_injection = var.apim_network_type != "None" && !var.is_apim_v2
  is_internal       = var.apim_network_type == "Internal"

  # APIM logger `endpointAddress` expects hostname (optionally with :port), not a
  # URL. Bicep does: replace(eventHubEndpoint, 'https://', ''). Terraform's
  # azurerm_api_management_logger.eventhub.endpoint_uri is forwarded verbatim,
  # so we strip the scheme + any trailing slash/port suffix here.
  eventhub_hostname = replace(replace(var.eventhub_endpoint_uri, "https://", ""), "/", "")
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
  }

  # Bicep parity: UserAssigned only (system-assigned identity dropped upstream;
  # all backend auth + RBAC uses the user-assigned MI).
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # VNet integration for Developer/Premium SKUs (non-V2).
  dynamic "virtual_network_configuration" {
    for_each = local.is_vnet_injection ? [1] : []
    content {
      subnet_id = var.apim_subnet_id
    }
  }

  virtual_network_type = local.is_vnet_injection ? var.apim_network_type : "None"

  # Bicep parity: customProperties — TLS/cipher hardening.
  # Disable TLS 1.0 / 1.1 / SSL 3.0 on both frontend and backend.
  # Disable weak ciphers (3DES, legacy RSA/CBC suites) on the frontend.
  # Skipped for Consumption SKU (customProperties unsupported there).
  dynamic "security" {
    for_each = var.sku_name == "Consumption" ? [] : [1]
    content {
      backend_ssl30_enabled = false
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
# APIM LOGGER: Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_api_management_logger" "app_insights" {
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id

  application_insights {
    # Bicep parity: prefer connection_string (correlates region+resource) when
    # available; fall back to instrumentation_key.
    connection_string   = var.app_insights_connection_string != "" ? var.app_insights_connection_string : null
    instrumentation_key = var.app_insights_connection_string == "" ? var.app_insights_instrumentation_key : null
  }
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Azure Monitor (Bicep parity — required for `azureMonitor`
# diagnostic destination on inference APIs). Not exposed by azurerm provider.
#
# We used to manage this with `azapi_resource`, but azapi does a GET-before-
# create and aborts with "already exists" whenever the logger is present in
# Azure but missing from local state (e.g. after a state reset, soft-deleted
# APIM rehydration, or when APIM auto-materialises the logger server-side).
# An ARM PUT is natively idempotent (exists → update, missing → create), so
# we drive it via `az rest` through a `terraform_data` that re-runs only when
# the parent APIM service or the logger body changes. This removes the
# "already exists" failure mode entirely without needing terraform import.
# -----------------------------------------------------------------------------

locals {
  azure_monitor_logger_body = jsonencode({
    properties = {
      loggerType  = "azureMonitor"
      description = "Azure Monitor logger for gateway diagnostics"
    }
  })

  # OS detection for cross-platform local-exec dispatch:
  # Windows abspaths look like `C:\...` (drive letter + `:`), Unix look like
  # `/...`. We pick a PowerShell interpreter on Windows and /bin/sh elsewhere.
  _tf_is_windows = length(regexall("^[A-Za-z]:[\\\\/]", abspath(path.root))) > 0

  azure_monitor_logger_url = "https://management.azure.com${azurerm_api_management.citadel.id}/loggers/azuremonitor?api-version=2024-05-01"
}

# --- POSIX (bash/sh) variant — Linux & macOS --------------------------------
resource "terraform_data" "azure_monitor_logger_posix" {
  count = local._tf_is_windows ? 0 : 1

  triggers_replace = [
    azurerm_api_management.citadel.id,
    local.azure_monitor_logger_body,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      APIM_ID     = azurerm_api_management.citadel.id
      LOGGER_BODY = local.azure_monitor_logger_body
      LOGGER_URL  = local.azure_monitor_logger_url
    }
    command = <<-EOT
      set -eu
      az rest --method PUT \
        --url "$${LOGGER_URL}" \
        --body "$${LOGGER_BODY}" \
        --headers "Content-Type=application/json" \
        > /dev/null
      echo "[apim] azuremonitor logger upserted on $${APIM_ID}"
    EOT
  }
}

# --- Windows (PowerShell) variant -------------------------------------------
resource "terraform_data" "azure_monitor_logger_windows" {
  count = local._tf_is_windows ? 1 : 0

  triggers_replace = [
    azurerm_api_management.citadel.id,
    local.azure_monitor_logger_body,
  ]

  provisioner "local-exec" {
    interpreter = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    environment = {
      APIM_ID     = azurerm_api_management.citadel.id
      LOGGER_BODY = local.azure_monitor_logger_body
      LOGGER_URL  = local.azure_monitor_logger_url
    }
    command = <<-EOT
      $ErrorActionPreference = 'Stop'
      az rest --method PUT `
        --url "$env:LOGGER_URL" `
        --body "$env:LOGGER_BODY" `
        --headers "Content-Type=application/json" `
        | Out-Null
      Write-Host "[apim] azuremonitor logger upserted on $env:APIM_ID"
    EOT
  }
}

# -----------------------------------------------------------------------------
# APIM LOGGER: Event Hub (for usage streaming)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_logger" "eventhub" {
  name                = "usage-eventhub-logger"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name

  eventhub {
    name                             = var.eventhub_usage_hub_name
    endpoint_uri                     = local.eventhub_hostname
    user_assigned_identity_client_id = var.managed_identity_client_id
  }
}

resource "azurerm_api_management_logger" "pii_eventhub" {
  count               = var.enable_pii_redaction ? 1 : 0
  name                = "pii-usage-eventhub-logger"
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name

  eventhub {
    name                             = var.eventhub_pii_hub_name
    endpoint_uri                     = local.eventhub_hostname
    user_assigned_identity_client_id = var.managed_identity_client_id
  }
}

# -----------------------------------------------------------------------------
# APIM DIAGNOSTIC SETTINGS (API-level logging verbosity)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_diagnostic" "global" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.citadel.name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage       = 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = var.log_verbosity
  operation_name_format     = "Url"

  frontend_request {
    body_bytes = var.log_body_bytes
    headers_to_log = [
      "Content-Type", "User-Agent", "x-ms-client-request-id"
    ]
  }

  frontend_response {
    body_bytes     = var.log_body_bytes
    headers_to_log = ["Content-Type", "x-ms-request-id"]
  }

  backend_request {
    body_bytes = var.log_body_bytes
  }

  backend_response {
    body_bytes = var.log_body_bytes
  }
}

# -----------------------------------------------------------------------------
# Bicep parity: apim.bicep sets `metrics: true` on the service-level
# applicationinsights diagnostic. The azurerm provider does not expose this
# property, so we PATCH it here. Without this flag, `<emit-metric>` and
# `<llm-emit-token-metric>` policies execute successfully but APIM drops the
# samples before forwarding them to App Insights (no customMetrics emitted).
# -----------------------------------------------------------------------------
resource "azapi_update_resource" "global_appinsights_metrics" {
  type        = "Microsoft.ApiManagement/service/diagnostics@2024-05-01"
  resource_id = "${azurerm_api_management.citadel.id}/diagnostics/applicationinsights"

  body = {
    properties = {
      metrics = true
    }
  }

  depends_on = [azurerm_api_management_diagnostic.global]
}

# -----------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
#
# Azure Policy (DeployIfNotExists) auto-creates a diagnostic setting named
# `diag-<apim>` on APIM instances. Using azapi_resource_action with PUT sends
# an ARM "Create or Update" that succeeds whether the resource exists or not.
# -----------------------------------------------------------------------------

resource "azapi_resource_action" "apim_diagnostics" {
  type        = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  resource_id = "${azurerm_api_management.citadel.id}/providers/Microsoft.Insights/diagnosticSettings/diag-${var.apim_name}"
  method      = "PUT"

  body = {
    properties = {
      workspaceId                = var.log_analytics_id
      logAnalyticsDestinationType = "Dedicated"
      logs = [
        { categoryGroup = "AllLogs", enabled = true }
      ]
      metrics = [
        { category = "AllMetrics", enabled = true }
      ]
    }
  }
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

# -----------------------------------------------------------------------------
# UNIVERSAL LLM API (sub-module)
# Bicep parity: ./inference-api.bicep called from apim.bicep with
# inferenceAPIType='OpenAIV1' (upstream default). The submodule imports the
# matching OpenAPI spec so all operations from the Bicep deployment are present.
# -----------------------------------------------------------------------------

locals {
  # Bicep parity: inference-api.bicep endpointPath + spec selection.
  universal_llm_api_path = (
    var.inference_api_type == "AzureOpenAI" ? "openai" :
    var.inference_api_type == "AzureAI" ? "inference" :
    var.inference_api_type == "OpenAI" ? "openai" :
    var.inference_api_type == "OpenAIV1" ? "models" : "models"
  )
  universal_llm_spec_path = (
    var.inference_api_type == "AzureOpenAI" ? "${path.module}/azure-openai-api/AIFoundryOpenAI.json" :
    var.inference_api_type == "AzureAI" ? "${path.module}/universal-llm-api/AIFoundryAzureAI.json" :
    var.inference_api_type == "OpenAI" ? "${path.module}/universal-llm-api/AIFoundryAzureAI.json" :
    var.inference_api_type == "OpenAIV1" ? "${path.module}/universal-llm-api/AIFoundryOpenAIV1.json" :
    "${path.module}/universal-llm-api/PassThrough.json"
  )
}

module "universal_llm" {
  source = "./universal-llm-api"

  apim_name             = azurerm_api_management.citadel.name
  apim_id               = azurerm_api_management.citadel.id
  resource_group_name   = var.resource_group_name
  subscription_required = !var.entra_auth_enabled
  has_llm_backends      = length(var.llm_backend_config) > 0

  # Bicep parity: inferenceAPIType (apim.bicep default 'OpenAIV1'). Selects the
  # OpenAPI spec + base path. OpenAIV1 -> AIFoundryOpenAIV1.json + 'models';
  # AzureAI -> AIFoundryAzureAI.json + 'inference'.
  inference_api_type = var.inference_api_type
  api_path           = local.universal_llm_api_path
  openapi_spec_path  = local.universal_llm_spec_path

  policy_xml_path                       = "${path.module}/policies/universal-llm-api-policy-v2.xml"
  deployments_op_policy_xml_path        = "${path.module}/policies/universal-llm-api-deployments-policy.xml"
  deployment_by_name_op_policy_xml_path = "${path.module}/policies/universal-llm-api-deployment-by-name-policy.xml"
  # OpenAIV1-only operations (listModels / retrieveModel)
  list_models_op_policy_xml_path        = "${path.module}/policies/universal-llm-api-deployments-policy.xml"
  retrieve_model_op_policy_xml_path     = "${path.module}/policies/universal-llm-api-deployment-by-name-policy.xml"

  app_insights_logger_id = azurerm_api_management_logger.app_insights.id
  # Azure Monitor logger is created via az-rest (terraform_data); construct
  # its ARM resource ID deterministically and depend on the upsert below.
  azure_monitor_logger_id = "${azurerm_api_management.citadel.id}/loggers/azuremonitor"

  policy_dependencies = [
    azurerm_api_management_policy_fragment.static,
    azurerm_api_management_policy_fragment.set_backend_pools,
    azurerm_api_management_policy_fragment.get_available_models,
    azurerm_api_management_policy_fragment.metadata_config,
    azurerm_api_management_named_value.uami_client_id,
    azurerm_api_management_named_value.entra_tenant_id,
    azurerm_api_management_named_value.entra_client_id,
    azurerm_api_management_named_value.entra_audience,
    azurerm_api_management_named_value.entra_auth_flag,
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}

# -----------------------------------------------------------------------------
# AZURE OPENAI COMPATIBILITY API (sub-module)
# Bicep parity: ./inference-api.bicep called from apim.bicep with
# inferenceAPIType='AzureOpenAI'. The submodule imports AIFoundryOpenAI.json
# so the full Azure OpenAI surface is present (deployments, deployment-by-name,
# completions, embeddings, chat/completions, audio/*, images/generations, ...).
# -----------------------------------------------------------------------------

module "azure_openai" {
  source = "./azure-openai-api"

  apim_name             = azurerm_api_management.citadel.name
  apim_id               = azurerm_api_management.citadel.id
  resource_group_name   = var.resource_group_name
  subscription_required = !var.entra_auth_enabled
  has_llm_backends      = length(var.llm_backend_config) > 0

  # Bicep loads the OpenAPI spec via loadJsonContent('./universal-llm-api/AIFoundryOpenAI.json'),
  # so the spec lives next to the universal-llm submodule's specs.
  openapi_spec_path                     = "${path.module}/azure-openai-api/AIFoundryOpenAI.json"
  policy_xml_path                       = "${path.module}/policies/azure-open-ai-api-policy.xml"
  deployments_op_policy_xml_path        = "${path.module}/policies/universal-llm-api-deployments-policy.xml"
  deployment_by_name_op_policy_xml_path = "${path.module}/policies/universal-llm-api-deployment-by-name-policy.xml"

  app_insights_logger_id  = azurerm_api_management_logger.app_insights.id
  azure_monitor_logger_id = "${azurerm_api_management.citadel.id}/loggers/azuremonitor"

  policy_dependencies = [
    azurerm_api_management_policy_fragment.static,
    azurerm_api_management_policy_fragment.set_backend_pools,
    azurerm_api_management_policy_fragment.get_available_models,
    azurerm_api_management_policy_fragment.metadata_config,
    azurerm_api_management_named_value.uami_client_id,
    azurerm_api_management_named_value.entra_tenant_id,
    azurerm_api_management_named_value.entra_client_id,
    azurerm_api_management_named_value.entra_audience,
    azurerm_api_management_named_value.entra_auth_flag,
    terraform_data.azure_monitor_logger_posix,
    terraform_data.azure_monitor_logger_windows,
  ]
}

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
  api_name            = module.universal_llm.api_name
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_api" "openai_default" {
  api_name            = module.azure_openai.api_name
  product_id          = azurerm_api_management_product.default_contract.product_id
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
}


# -----------------------------------------------------------------------------
# APIM REDIS CACHE (Bicep parity: `service/caches` resource)
# Links Azure Managed Redis to APIM for semantic caching. Created only when
# a connection string is provided.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_redis_cache" "default" {
  count             = var.redis_cache_connection_string != "" ? 1 : 0
  name              = "Default"
  api_management_id = azurerm_api_management.citadel.id
  connection_string = var.redis_cache_connection_string
  description       = "Azure Managed Redis for APIM semantic cache"
}
