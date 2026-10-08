# =============================================================================
# AI Citadel Governance Hub - Root Module
# =============================================================================
# Orchestrates all modules for the Citadel Governance Hub deployment.
# Mirrors the architecture from the Azure-Samples Bicep accelerator.
# =============================================================================

# =============================================================================
# NAMING — every resource name comes from modules/naming (v1 convention =
# the names this repository has always generated). Explicit name variables and
# var.name_overrides win.
# =============================================================================

module "naming" {
  source = "./modules/naming"

  environment_name       = var.environment_name
  resource_group_name    = var.resource_group_name
  subscription_id        = var.subscription_id
  legacy_suffix          = random_string.suffix.result
  foundry_instance_names = [for c in var.ai_foundry_instances : c.name]

  # Dedicated name inputs win over var.name_overrides only when they are set.
  name_overrides = merge(var.name_overrides, {
    for k, v in {
      resource_group     = var.resource_group_name
      apim               = local.apim_cfg.name
      cosmos             = var.cosmos_db_account_name
      eventhub_namespace = var.eventhub_namespace_name
      log_analytics      = var.log_analytics_name
      key_vault          = var.key_vault_name
      virtual_network    = local.network_cfg.vnet_name
    } : k => v if v != null && v != ""
  })
}

locals {
  names = module.naming.names

  # Short aliases kept so the rest of the root module reads as before.
  resource_group_name = local.names.resource_group
  apim_service_name   = local.names.apim
  cosmos_db_name      = local.names.cosmos
  eventhub_ns_name    = local.names.eventhub_namespace
  log_analytics_name  = local.names.log_analytics
  key_vault_name      = local.names.key_vault
  vnet_name           = local.names.virtual_network

  # Merged tags
  default_tags = {
    "azd-env-name" = var.environment_name
    "Solution"     = "ai-citadel-governance-hub"
    "ManagedBy"    = "Terraform"
  }
  all_tags = merge(local.default_tags, var.tags)

  # Determine APIM SKU family
  is_apim_v2   = contains(["StandardV2", "PremiumV2"], local.apim_cfg.sku)
  is_apim_vnet = contains(["Developer", "Premium"], local.apim_cfg.sku)

  # Create private DNS zones when not using existing
  # alz_spoke: the platform owns the private DNS zones.
  create_dns_zones = length(local.network_cfg.private_dns_zone_ids) == 0 && local.network_cfg.private_dns_resource_group_name == "" && !local.network_cfg.alz_spoke
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Auto-detect the public IP of the machine running `terraform apply`.
# Only instantiated when var.kv_auto_detect_deployer_ip = true so normal
# runs don't make an outbound HTTP call.
data "http" "deployer_ip" {
  count = var.kv_auto_detect_deployer_ip ? 1 : 0
  url   = "https://api.ipify.org"

  request_headers = {
    Accept = "text/plain"
  }
}

# =============================================================================
# RESOURCE GROUP
# =============================================================================

resource "azurerm_resource_group" "citadel" {
  count    = var.use_existing_resource_group ? 0 : 1
  name     = local.resource_group_name
  location = var.location
  tags     = local.all_tags
}

data "azurerm_resource_group" "existing" {
  count = var.use_existing_resource_group ? 1 : 0
  name  = local.resource_group_name
}

locals {
  resource_group_name_resolved = var.use_existing_resource_group ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.citadel[0].name
  resource_group_id            = var.use_existing_resource_group ? data.azurerm_resource_group.existing[0].id : azurerm_resource_group.citadel[0].id
}

# =============================================================================
# RANDOM SUFFIX for globally unique names
# =============================================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# USER-ASSIGNED MANAGED IDENTITIES
# Bicep parity:
#   - `apim` UAMI (Bicep: managed-identity-apim.bicep) — used by APIM for
#     outbound backend authentication to Foundry, ContentSafety, Language,
#     EventHub (logger), Key Vault.
#   - `usage` UAMI (Bicep: managed-identity-usage.bicep) — used by the Logic
#     App for Cosmos DB SQL data plane + Storage + EventHub receiver.
# =============================================================================

module "identity" {
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "0.5.3"
  for_each = { apim = local.names.uami_apim, usage = local.names.uami_usage }

  name                = each.value
  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags
  enable_telemetry    = var.enable_telemetry
}

# Backwards-compat alias used by downstream outputs. Kept during the split so
# existing callers / outputs continue to function without churn. Prefer the
# explicit `.apim` / `.usage` identities going forward.
locals {
  apim_identity_id        = module.identity["apim"].resource_id
  apim_identity_client_id = module.identity["apim"].client_id
  apim_identity_principal = module.identity["apim"].principal_id

  usage_identity_id        = module.identity["usage"].resource_id
  usage_identity_client_id = module.identity["usage"].client_id
  usage_identity_principal = module.identity["usage"].principal_id
}

# BYO Log Analytics workspace, possibly in another subscription (provider alias).
data "azurerm_log_analytics_workspace" "byo" {
  provider            = azurerm.loganalytics
  count               = local.monitoring_cfg.byo_workspace ? 1 : 0
  name                = try(split("/", local.monitoring_cfg.workspace_id)[8], "")
  resource_group_name = try(split("/", local.monitoring_cfg.workspace_id)[4], "")
}

# =============================================================================
# MODULE: MONITORING (Log Analytics + Application Insights)
# =============================================================================

module "monitoring" {
  source = "./modules/monitoring"


  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  log_analytics_name = local.log_analytics_name
  existing_log_analytics_workspace = local.monitoring_cfg.byo_workspace ? {
    id           = local.monitoring_cfg.workspace_id
    workspace_id = data.azurerm_log_analytics_workspace.byo[0].workspace_id
  } : null

  environment_name  = var.environment_name
  enable_telemetry  = var.enable_telemetry
  create_dashboards = local.monitoring_cfg.app_insights_dashboards
  subscription_id   = var.subscription_id

  # AMPLS (Bicep parity: useAzureMonitorPrivateLinkScope)
  use_azure_monitor_private_link_scope = local.monitoring_cfg.private_link_scope
  ampls_subnet_id                      = local.monitoring_cfg.private_link_scope ? local.network.pe_subnet_id : ""
  ampls_dns_zone_id_monitor            = local.monitoring_cfg.private_link_scope ? lookup(module.private_dns.zone_ids, "monitor", "") : ""
}

# =============================================================================
# MODULE: SECURITY (Key Vault + Managed Identity Roles)
# =============================================================================

module "security" {
  source = "./modules/security"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  key_vault_name     = local.key_vault_name
  key_vault_sku      = var.key_vault_sku
  tenant_id          = data.azurerm_client_config.current.tenant_id
  deployer_object_id = data.azurerm_client_config.current.object_id

  managed_identity_principal_id = local.apim_identity_principal

  subnet_id = local.network.pe_subnet_id

  dns_zone_id_key_vault            = lookup(module.private_dns.zone_ids, "key_vault", "")
  dns_zone_group_managed_by_policy = local.network_cfg.zone_groups_managed_by_policy
  enable_telemetry                 = var.enable_telemetry

  # Bicep parity: grant each Foundry system-assigned MI KV Secrets User
  foundry_principal_ids   = module.foundry.foundry_principal_ids
  foundry_principal_count = length(var.ai_foundry_instances)

  # Purge protection and RBAC authorization settings (Bicep parity: enablePurgeProtection, enableRbacAuthorization)
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled
  rbac_authorization_enabled = var.rbac_authorization_enabled

  # Key Vault public network access:
  # If the deployer IP allowlist is active (explicit CIDRs OR auto-detect),
  # we MUST enable public network access — otherwise Azure ignores `ip_rules`
  # entirely ("Disable public access" mode) and the bootstrap secret writes
  # will still 403. Combined with default_action="Deny" this is still safe:
  # only the allowlisted IPs + private endpoints can reach the data plane.
  public_network_access_enabled = (
    length(var.kv_deployer_ip_rules) > 0 || var.kv_auto_detect_deployer_ip
  ) ? true : var.kv_public_network_access_enabled
  network_acl_default_action = var.network_acl_default_action

  # Optional deployer IP allowlist for bootstrap data-plane writes.
  # Combines any explicitly provided CIDRs with an auto-detected runner IP
  # (when kv_auto_detect_deployer_ip = true).
  ip_rules = distinct(concat(
    var.kv_deployer_ip_rules,
    var.kv_auto_detect_deployer_ip ? ["${chomp(data.http.deployer_ip[0].response_body)}/32"] : []
  ))

  # Placeholder `apim-gateway-key` secret — disabled by default (nothing in
  # this stack consumes it; it only exists to mirror Bicep behaviour). Opt
  # in only if you have downstream tooling that reads the secret directly.
  create_apim_gateway_key_secret = var.create_apim_gateway_key_secret
}

# =============================================================================
# MODULE: COSMOS DB
# =============================================================================

module "cosmosdb" {
  source = "./modules/cosmosdb"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  account_name          = local.cosmos_db_name
  public_network_access = local.usage_cfg.cosmos.public_network_access

  local_authentication_enabled = local.usage_cfg.cosmos.local_auth_enabled

  # Identity (for RBAC - Cosmos DB Built-in Data Contributor on Usage MI)
  managed_identity_principal_id = local.usage_identity_principal

  subnet_id = local.network.pe_subnet_id

  dns_zone_group_managed_by_policy = local.network_cfg.zone_groups_managed_by_policy
  enable_telemetry                 = var.enable_telemetry
  dns_zone_id                      = lookup(module.private_dns.zone_ids, "cosmos_db", "")

  log_analytics_id = module.monitoring.log_analytics_id
}

# =============================================================================
# MODULE: EVENT HUB
# =============================================================================

module "eventhub" {
  source = "./modules/eventhub"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  namespace_name        = local.eventhub_ns_name
  capacity_units        = local.usage_cfg.eventhub.capacity
  public_network_access = local.usage_cfg.eventhub.public_network_access

  # Identities (Bicep parity): APIM MI = Sender, Usage MI = Receiver + Owner
  apim_identity_principal_id  = local.apim_identity_principal
  usage_identity_principal_id = local.usage_identity_principal

  subnet_id = local.network.pe_subnet_id

  dns_zone_group_managed_by_policy = local.network_cfg.zone_groups_managed_by_policy
  enable_telemetry                 = var.enable_telemetry
  dns_zone_id                      = lookup(module.private_dns.zone_ids, "event_hub", "")

  log_analytics_id = module.monitoring.log_analytics_id

  # Optional DR pairing (Bicep parity: disasterRecoveryConfig)
  disaster_recovery_config = local.usage_cfg.eventhub.disaster_recovery
}

# =============================================================================
# MODULE: API Center
# =============================================================================

module "apic" {
  source = "./modules/apic"

  resource_group_id = local.resource_group_id
  tags              = local.all_tags
  api_center_name   = local.names.api_center

  # Feature flags
  enable_api_center = local.features.api_center
  apic_location     = var.apic_location != "" ? var.apic_location : var.location

  # SKUs
  api_center_sku = var.api_center_sku

  # Managed identity for RBAC

  # Networking

}

# =============================================================================
# MODULE: FOUNDRY (AI Foundry accounts, projects, models, connections)
# =============================================================================

module "foundry" {
  source = "./modules/foundry"

  enable_telemetry       = var.enable_telemetry
  outbound_allowed_fqdns = var.foundry_outbound_allowed_fqdns

  resource_group_name = local.resource_group_name_resolved
  resource_group_id   = local.resource_group_id
  location            = var.location
  tags                = local.all_tags
  account_names       = module.naming.foundry_account_names

  foundry_external_access = var.ai_foundry_external_access

  foundry_instances = var.ai_foundry_instances
  foundry_models    = var.ai_foundry_models

  # RBAC principals
  apim_principal_id  = local.apim_identity_principal
  deployer_object_id = data.azurerm_client_config.current.object_id

  # Monitoring / App Insights connection
  log_analytics_id                 = module.monitoring.log_analytics_id
  app_insights_id                  = module.monitoring.foundry_app_insights_id
  app_insights_instrumentation_key = module.monitoring.foundry_app_insights_instrumentation_key

  # Networking
  subnet_id                         = local.network.pe_subnet_id
  dns_zone_ids                      = module.private_dns.zone_ids
  foundry_network_injection_enabled = var.foundry_network_injection_enabled
  agent_subnet_id                   = local.network.agent_subnet_id

  # Foundry project -> APIM connections (ApiKey = dedicated foundry-apim-connection subscription)
  enable_apim_connections = var.enable_foundry_apim_connection
  apim_service_name       = local.apim_service_name
  apim_gateway_url        = module.apim.gateway_url
  apim_primary_key        = module.apim.foundry_connection_primary_key
  apim_connections        = var.foundry_apim_connections
}

# =============================================================================
# MODULE: REDIS (Azure Managed Redis — semantic cache)
# Bicep parity: bicep/infra/modules/redis/redis.bicep (conditional on enableRedisCache)
# =============================================================================

module "redis" {
  count  = local.features.semantic_cache ? 1 : 0
  source = "./modules/redis"

  name                = local.names.redis
  location            = var.location
  resource_group_name = local.resource_group_name_resolved
  tags                = local.all_tags

  sku_name              = var.redis_sku_name
  sku_capacity          = var.redis_sku_capacity
  public_network_access = var.redis_public_network_access
  minimum_tls_version   = var.redis_minimum_tls_version

  subnet_id   = local.network.pe_subnet_id
  dns_zone_id = lookup(module.private_dns.zone_ids, "redis", "")
}

# =============================================================================
# MODULE: ENTRA ID SETUP (optional, entra-id-setup/setup.ps1 parity)
# =============================================================================

module "entra_id" {
  count  = var.enable_entra_id_setup ? 1 : 0
  source = "./modules/entra-id"

  environment_name            = var.environment_name
  app_display_name_prefix     = var.entra_app_display_name_prefix
  key_vault_id                = module.security.key_vault_id_for_secrets
  client_secret_name          = var.entra_client_secret_name
  client_secret_rotation_days = var.entra_client_secret_rotation_days
}

locals {
  # When the Entra module is enabled, its outputs override the bare jwt_* vars
  # so APIM JWT-* named values get populated automatically.
  effective_enable_jwt_auth = var.enable_entra_id_setup ? true : var.enable_jwt_auth
  effective_jwt_tenant_id = var.enable_entra_id_setup ? (
    length(module.entra_id) > 0 ? module.entra_id[0].tenant_id : var.jwt_tenant_id
  ) : var.jwt_tenant_id
  effective_jwt_app_registration_id = var.enable_entra_id_setup ? (
    length(module.entra_id) > 0 ? module.entra_id[0].client_id : var.jwt_app_registration_id
  ) : var.jwt_app_registration_id
}

# =============================================================================
# AUTO-DERIVE llm_backend_config FROM FOUNDRY
# -----------------------------------------------------------------------------
#
# APIM backends + pools are synthesized automatically from:
#   - var.ai_foundry_instances (one backend per instance)
#   - var.ai_foundry_models            (grouped by ai_service_index)
#   - module.foundry.foundry_endpoints (late-bound — known after apply, which
#     is fine: `for_each` keys use backend_id, not endpoint)
#
# Users can still override (or extend) via:
#   - var.llm_backend_config   — FULL override (replaces auto-derived entirely)
#   - var.extra_llm_backends   — APPENDED to the auto list (Foundry + external)
# =============================================================================

locals {
  auto_llm_backends = [
    for i, inst in var.ai_foundry_instances : {
      backend_id   = "foundry-${inst.location}-${i}"
      backend_type = "ai-foundry"
      endpoint     = module.foundry.foundry_endpoints[i]
      auth_scheme  = "managedIdentity"
      auth_type    = "managed-identity"
      auth_config  = {}
      priority     = i == 0 ? 1 : 2
      weight       = 100
      supported_models = [
        for m in var.ai_foundry_models : {
          name         = m.name
          sku          = try(m.sku, "GlobalStandard")
          capacity     = try(m.capacity, 100)
          modelFormat  = "OpenAI"
          modelVersion = m.version
          apiVersion   = "2024-02-15-preview"
          timeout      = 120
        } if try(m.ai_service_index, 0) == i
      ]
    }
  ]

  effective_llm_backend_config = length(var.llm_backend_config) > 0 ? var.llm_backend_config : concat(
    local.auto_llm_backends,
    var.extra_llm_backends,
  )
}

# =============================================================================
# MODULE: APIM TELEMETRY — loggers + service-level diagnostics
# =============================================================================

module "apim_telemetry" {
  source = "./modules/apim-telemetry"

  api_management_id   = module.apim.apim_id
  api_management_name = module.apim.apim_name
  resource_group_name = local.resource_group_name_resolved

  app_insights_id                  = module.monitoring.app_insights_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  app_insights_instrumentation_key = module.monitoring.app_insights_instrumentation_key
  log_analytics_id                 = module.monitoring.log_analytics_id

  eventhub_endpoint_uri      = module.eventhub.endpoint_uri
  eventhub_usage_hub_name    = module.eventhub.apim_usage_hub_name
  eventhub_pii_hub_name      = module.eventhub.pii_usage_hub_name
  enable_pii_redaction       = local.features.pii_redaction
  managed_identity_client_id = local.apim_identity_client_id

  log_verbosity  = var.apim_log_verbosity
  log_body_bytes = var.apim_log_body_bytes
}

# =============================================================================
# MODULE: LLM ROUTING — backends, pools and generated routing fragments
# =============================================================================

module "llm_routing" {
  source = "./modules/llm-routing"

  api_management_id          = module.apim.apim_id
  managed_identity_client_id = local.apim_identity_client_id
  llm_backend_config         = local.effective_llm_backend_config
  configure_circuit_breaker  = var.configure_circuit_breaker
}

# =============================================================================
# MODULE: API MANAGEMENT
# =============================================================================

module "apim" {
  source = "./modules/apim"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  subscription_id                  = var.subscription_id
  enable_telemetry                 = var.enable_telemetry
  dns_zone_group_managed_by_policy = local.network_cfg.zone_groups_managed_by_policy

  apim_name       = local.apim_service_name
  sku_name        = local.apim_cfg.sku
  sku_capacity    = local.apim_cfg.capacity
  publisher_email = local.apim_cfg.publisher_email
  publisher_name  = local.apim_cfg.publisher_name

  # Networking
  apim_network_type             = local.apim_network_type
  is_apim_v2                    = local.is_apim_v2
  apim_subnet_id                = local.network.apim_subnet_id
  pe_subnet_id                  = local.network.pe_subnet_id
  vnet_id                       = local.network.vnet_id
  apim_v2_use_private_endpoint  = local.apim_cfg.private_endpoint
  apim_v2_public_network_access = local.apim_cfg.public_network_access

  # Identity
  managed_identity_id        = local.apim_identity_id
  managed_identity_client_id = local.apim_identity_client_id

  # Monitoring

  # Redis (semantic cache) — optional
  enable_redis_cache            = local.features.semantic_cache
  redis_cache_connection_string = local.features.semantic_cache ? module.redis[0].connection_string : ""

  # Availability zones (Bicep parity: Premium + skuCount>1)
  apim_zones = local.apim_cfg.sku == "Premium" && local.apim_cfg.capacity > 1 ? (
    local.apim_cfg.capacity == 2 ? ["1", "2"] : ["1", "2", "3"]
  ) : []

  # Integrations
  pii_service_endpoint    = local.features.pii_redaction ? module.foundry.primary_foundry_endpoint : ""
  content_safety_endpoint = local.features.content_safety ? module.foundry.primary_foundry_endpoint : ""
  enable_pii_redaction    = local.features.pii_redaction
  enable_content_safety   = local.features.content_safety

  # Universal LLM API inference contract (Bicep: inferenceAPIType)

  # Auth
  entra_auth_enabled = var.entra_auth_enabled
  entra_tenant_id    = var.entra_tenant_id
  entra_client_id    = var.entra_client_id
  entra_audience     = var.entra_audience

  # Logging

  # DNS
  dns_zone_id_apim = lookup(module.private_dns.zone_ids, "apim_gateway", "")
  # Internal-mode APIM hostname zones; skipped when DNS is managed centrally (BYO zones).
  create_internal_dns = local.create_dns_zones

  # APIM logic plane (§19.12 — Bicep parity for llm-backends/pools, fragments,
  # extra APIs, MCP, API Center onboarding)
  default_product_api_names = {
    universal_llm = module.api["universal-llm-api"].name
    azure_openai  = module.api["azure-openai-api"].name
  }
  ai_search_instances       = [for s in var.ai_search_instances : { name = s.name, url = s.endpoint, description = "AI Search backend" }]
  enable_azure_ai_search    = local.features.azure_ai_search
  enable_embeddings_backend = local.features.embeddings_backend
  embeddings_backend_url    = var.embeddings_backend_url
  is_mcp_sample_deployed    = local.features.mcp_sample
  ms_learn_mcp_backend_url  = var.ms_learn_mcp_backend_url

  enable_jwt_auth         = local.effective_enable_jwt_auth
  jwt_tenant_id           = local.effective_jwt_tenant_id
  jwt_app_registration_id = local.effective_jwt_app_registration_id
  azure_login_endpoint    = var.azure_login_endpoint


  enable_foundry_apim_connection = var.enable_foundry_apim_connection
}

# =============================================================================
# MODULE: LOGIC APP (Usage Ingestion)
# =============================================================================

module "logic_app" {
  source = "./modules/logic-app"

  resource_group_id   = local.resource_group_id
  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags
  environment_name    = var.environment_name
  names = {
    storage_account         = local.names.storage_logic
    logic_app               = local.names.logic_app
    content_share           = local.names.logic_content_share
    app_service_plan        = local.names.app_service_plan
    app_service_environment = local.names.app_service_environment
    code_artifact           = local.names.logic_app_code_artifact
  }

  sku_size = local.usage_cfg.logic_app.ws_sku

  # Hosting model — ASE v3 enables keyless (shared-key disabled) runtime storage
  enable_telemetry                 = var.enable_telemetry
  hosting_model                    = local.usage_cfg.logic_app.hosting_model
  ase_subnet_id                    = local.network.ase_subnet_id
  vnet_id                          = local.network.vnet_id
  ase_sku_size                     = local.usage_cfg.logic_app.ase_sku
  ase_worker_count                 = local.usage_cfg.logic_app.worker_count
  ase_internal_load_balancing_mode = local.usage_cfg.ase.internal_load_balancing_mode
  ase_zone_redundant               = local.usage_cfg.ase.zone_redundant
  ase_create_private_dns_zone      = local.usage_cfg.ase.create_private_dns_zone

  # Networking
  subnet_id    = local.network.logic_app_subnet_id
  pe_subnet_id = local.network.pe_subnet_id

  dns_zone_id_blob  = lookup(module.private_dns.zone_ids, "storage_blob", "")
  dns_zone_id_file  = lookup(module.private_dns.zone_ids, "storage_file", "")
  dns_zone_id_table = lookup(module.private_dns.zone_ids, "storage_table", "")
  dns_zone_id_queue = lookup(module.private_dns.zone_ids, "storage_queue", "")

  # Integrations
  eventhub_endpoint_host      = "${module.eventhub.namespace_name}.servicebus.windows.net"
  eventhub_ai_usage_hub_name  = module.eventhub.apim_usage_hub_name
  eventhub_pii_usage_hub_name = module.eventhub.pii_usage_hub_name

  cosmos_db_endpoint     = module.cosmosdb.endpoint
  cosmos_db_account_name = module.cosmosdb.account_name
  cosmos_db_account_id   = module.cosmosdb.account_id

  # cosmos container names
  cosmos_db_database_name       = module.cosmosdb.database_name
  cosmos_db_container_config    = module.cosmosdb.config_container_name
  cosmos_db_container_usage     = module.cosmosdb.usage_container_name
  cosmos_db_container_pii       = module.cosmosdb.pii_container_name
  cosmos_db_container_llm_usage = module.cosmosdb.llm_usage_container_name

  app_insights_connection_string = module.monitoring.app_insights_connection_string
  apim_app_insights_name         = module.monitoring.app_insights_name
  apim_app_insights_rg           = local.resource_group_name_resolved
  subscription_id                = var.subscription_id

  content_share_name = local.usage_cfg.logic_app.content_share_name

  # Workflow-code publish. Defaults to the
  # vendored accelerator project under logicapp-src/usage-ingestion-logicapp.
  enable_code_deploy = local.usage_cfg.logic_app.code_deploy
  code_source_path   = local.usage_cfg.logic_app.code_source_path != "" ? local.usage_cfg.logic_app.code_source_path : "${path.root}/logicapp-src/usage-ingestion-logicapp"

  # Identity (Logic App uses the usage UAMI per Bicep managed-identity-usage.bicep)
  managed_identity_id           = local.usage_identity_id
  managed_identity_client_id    = local.usage_identity_client_id
  managed_identity_principal_id = local.usage_identity_principal

  log_analytics_id = module.monitoring.log_analytics_id
}
