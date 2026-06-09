# =============================================================================
# AI Citadel Governance Hub - Root Module
# =============================================================================
# Orchestrates all modules for the Citadel Governance Hub deployment.
# Mirrors the architecture from the Azure-Samples Bicep accelerator.
# =============================================================================

locals {
  # Generate a unique hash for resource naming
  resource_token = substr(sha256("${var.resource_group_name}-${var.environment_name}-${var.subscription_id}"), 0, 10)

  # Default resource names (auto-generated if not specified)
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.environment_name}"
  apim_service_name     = var.apim_service_name != "" ? var.apim_service_name : "apim-${local.resource_token}"
  cosmos_db_name        = var.cosmos_db_account_name != "" ? var.cosmos_db_account_name : "cosmos-${local.resource_token}"
  eventhub_ns_name      = var.eventhub_namespace_name != "" ? var.eventhub_namespace_name : "evhns-${local.resource_token}"
  log_analytics_name    = var.log_analytics_name != "" ? var.log_analytics_name : "law-${local.resource_token}"
  key_vault_name        = var.key_vault_name != "" ? var.key_vault_name : "kv-${local.resource_token}"
  vnet_name             = var.vnet_name != "" ? var.vnet_name : "vnet-${var.environment_name}"

  # Merged tags
  default_tags = {
    "azd-env-name"    = var.environment_name
    "Solution"        = "ai-citadel-governance-hub"
    "ManagedBy"       = "Terraform"
  }
  all_tags = merge(local.default_tags, var.tags)

  # Determine APIM SKU family
  is_apim_v2    = contains(["StandardV2", "PremiumV2"], var.apim_sku)
  is_apim_vnet  = contains(["Developer", "Premium"], var.apim_sku)

  # Create private DNS zones when not using existing
  create_dns_zones = length(var.existing_private_dns_zones) == 0 && var.dns_zone_rg == ""
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

resource "azurerm_user_assigned_identity" "apim" {
  name                = "id-apim-${var.environment_name}-${random_string.suffix.result}"
  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags
}

resource "azurerm_user_assigned_identity" "usage" {
  name                = "id-logicapp-${var.environment_name}-${random_string.suffix.result}"
  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags
}

# Backwards-compat alias used by downstream outputs. Kept during the split so
# existing callers / outputs continue to function without churn. Prefer the
# explicit `.apim` / `.usage` identities going forward.
locals {
  apim_identity_id        = azurerm_user_assigned_identity.apim.id
  apim_identity_client_id = azurerm_user_assigned_identity.apim.client_id
  apim_identity_principal = azurerm_user_assigned_identity.apim.principal_id

  usage_identity_id        = azurerm_user_assigned_identity.usage.id
  usage_identity_client_id = azurerm_user_assigned_identity.usage.client_id
  usage_identity_principal = azurerm_user_assigned_identity.usage.principal_id
}

# =============================================================================
# MODULE: NETWORKING
# =============================================================================

module "networking" {
  source = "./modules/networking"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  # VNet configuration
  use_existing_vnet  = var.use_existing_vnet
  existing_vnet_rg   = var.existing_vnet_rg
  vnet_name          = local.vnet_name
  vnet_address_prefix = var.vnet_address_prefix

  # Subnets
  apim_subnet_name           = var.apim_subnet_name
  apim_subnet_prefix         = var.apim_subnet_prefix
  pe_subnet_name             = var.private_endpoint_subnet_name
  pe_subnet_prefix           = var.private_endpoint_subnet_prefix
  logic_app_subnet_name      = var.logic_app_subnet_name
  logic_app_subnet_prefix    = var.logic_app_subnet_prefix
  enable_agent_subnet        = var.enable_agent_subnet
  agent_subnet_name          = var.agent_subnet_name
  agent_subnet_prefix        = var.agent_subnet_prefix

  # APIM network type
  apim_network_type = var.apim_network_type
  is_apim_vnet      = local.is_apim_vnet

  # DNS
  create_dns_zones           = local.create_dns_zones
  dns_zone_rg                = var.dns_zone_rg
  dns_subscription_id        = var.dns_subscription_id
  existing_private_dns_zones = var.existing_private_dns_zones
}

# =============================================================================
# MODULE: MONITORING (Log Analytics + Application Insights)
# =============================================================================

module "monitoring" {
  source = "./modules/monitoring"

  providers = {
    azurerm              = azurerm
    azurerm.loganalytics = azurerm.loganalytics
  }

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  log_analytics_name          = local.log_analytics_name
  use_existing_log_analytics  = var.use_existing_log_analytics
  existing_log_analytics_id   = var.existing_log_analytics_id

  environment_name            = var.environment_name
  create_dashboards           = var.create_app_insights_dashboards
  subscription_id             = var.subscription_id

  # AMPLS (Bicep parity: useAzureMonitorPrivateLinkScope)
  use_azure_monitor_private_link_scope = var.use_azure_monitor_private_link_scope
  ampls_subnet_id                      = var.use_azure_monitor_private_link_scope ? module.networking.pe_subnet_id : ""
  ampls_dns_zone_id_monitor            = var.use_azure_monitor_private_link_scope ? module.networking.dns_zone_ids["monitor"] : ""
}

# =============================================================================
# MODULE: SECURITY (Key Vault + Managed Identity Roles)
# =============================================================================

module "security" {
  source = "./modules/security"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  key_vault_name    = local.key_vault_name
  key_vault_sku     = var.key_vault_sku
  tenant_id         = data.azurerm_client_config.current.tenant_id
  deployer_object_id = data.azurerm_client_config.current.object_id

  managed_identity_principal_id = local.apim_identity_principal
  managed_identity_id           = local.apim_identity_id

  subnet_id = module.networking.pe_subnet_id
  vnet_id   = module.networking.vnet_id

  dns_zone_id_key_vault = module.networking.dns_zone_ids["key_vault"]

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

  account_name         = local.cosmos_db_name
  throughput_rus       = var.cosmos_db_rus
  public_network_access = var.cosmos_db_public_access

  # Identity (for RBAC - Cosmos DB Built-in Data Contributor on Usage MI)
  managed_identity_principal_id = local.usage_identity_principal

  subnet_id = module.networking.pe_subnet_id
  vnet_id   = module.networking.vnet_id

  dns_zone_id = module.networking.dns_zone_ids["cosmos_db"]

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

  namespace_name       = local.eventhub_ns_name
  capacity_units       = var.eventhub_capacity_units
  partition_count      = var.eventhub_partition_count
  public_network_access = var.eventhub_network_access

  # Identities (Bicep parity): APIM MI = Sender, Usage MI = Receiver + Owner
  apim_identity_principal_id  = local.apim_identity_principal
  usage_identity_principal_id = local.usage_identity_principal

  subnet_id = module.networking.pe_subnet_id
  vnet_id   = module.networking.vnet_id

  dns_zone_id = module.networking.dns_zone_ids["event_hub"]

  log_analytics_id = module.monitoring.log_analytics_id

  # Optional DR pairing (Bicep parity: disasterRecoveryConfig)
  disaster_recovery_config = var.eventhub_disaster_recovery_config
}

# =============================================================================
# MODULE: API Center
# =============================================================================

module "apic" {
  source = "./modules/apic"

  resource_group_name = local.resource_group_name_resolved
  resource_group_id   = local.resource_group_id
  location            = var.location
  tags                = local.all_tags
  environment_name    = var.environment_name
  random_suffix       = random_string.suffix.result

  # Feature flags
  enable_api_center     = var.enable_api_center
  apic_location         = var.apic_location != "" ? var.apic_location : var.location

  # SKUs
  api_center_sku       = var.api_center_sku

  # Managed identity for RBAC
  managed_identity_principal_id = local.apim_identity_principal

  # Networking
  subnet_id = module.networking.pe_subnet_id
  vnet_id   = module.networking.vnet_id

  dns_zone_ids = module.networking.dns_zone_ids
}

# =============================================================================
# MODULE: FOUNDRY (AI Foundry accounts, projects, models, connections)
# =============================================================================

module "foundry" {
  source = "./modules/foundry"

  resource_group_name = local.resource_group_name_resolved
  resource_group_id   = local.resource_group_id
  location            = var.location
  tags                = local.all_tags
  environment_name    = var.environment_name
  random_suffix       = random_string.suffix.result

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
  subnet_id    = module.networking.pe_subnet_id
  dns_zone_ids = module.networking.dns_zone_ids
  foundry_network_injection_enabled = var.foundry_network_injection_enabled
  agent_subnet_id = module.networking.agent_subnet_id
}

# =============================================================================
# MODULE: REDIS (Azure Managed Redis — semantic cache)
# Bicep parity: bicep/infra/modules/redis/redis.bicep (conditional on enableRedisCache)
# =============================================================================

module "redis" {
  count  = var.enable_redis_cache ? 1 : 0
  source = "./modules/redis"

  name                = "redis-${var.environment_name}-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = local.resource_group_name_resolved
  tags                = local.all_tags

  sku_name              = var.redis_sku_name
  sku_capacity          = var.redis_sku_capacity
  public_network_access = var.redis_public_network_access
  minimum_tls_version   = var.redis_minimum_tls_version

  subnet_id   = module.networking.pe_subnet_id
  dns_zone_id = module.networking.dns_zone_ids["redis"]

  depends_on = [module.networking]
}

# =============================================================================
# MODULE: ENTRA ID SETUP (optional, entra-id-setup/setup.ps1 parity)
# =============================================================================

module "entra_id" {
  count  = var.enable_entra_id_setup ? 1 : 0
  source = "./modules/entra-id"

  environment_name            = var.environment_name
  app_display_name_prefix     = var.entra_app_display_name_prefix
  key_vault_id                = module.security.key_vault_id
  client_secret_name          = var.entra_client_secret_name
  client_secret_rotation_days = var.entra_client_secret_rotation_days

  depends_on = [module.security]
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
# MODULE: API MANAGEMENT
# =============================================================================

module "apim" {
  source = "./modules/apim"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags

  apim_name        = local.apim_service_name
  sku_name         = var.apim_sku
  sku_capacity     = var.apim_sku_units
  publisher_email  = var.apim_publisher_email
  publisher_name   = var.apim_publisher_name

  # Networking
  apim_network_type          = var.apim_network_type
  is_apim_v2                 = local.is_apim_v2
  apim_subnet_id             = module.networking.apim_subnet_id
  pe_subnet_id               = module.networking.pe_subnet_id
  vnet_id                    = module.networking.vnet_id
  apim_v2_use_private_endpoint = var.apim_v2_use_private_endpoint
  apim_v2_public_network_access = var.apim_v2_public_network_access

  # Identity
  managed_identity_id        = local.apim_identity_id
  managed_identity_client_id = local.apim_identity_client_id

  # Monitoring
  app_insights_id                  = module.monitoring.app_insights_id
  app_insights_instrumentation_key = module.monitoring.app_insights_instrumentation_key
  app_insights_connection_string   = module.monitoring.app_insights_connection_string

  # Redis (semantic cache) — optional
  redis_cache_connection_string = var.enable_redis_cache ? module.redis[0].connection_string : ""

  # Availability zones (Bicep parity: Premium + skuCount>1)
  apim_zones = var.apim_sku == "Premium" && var.apim_sku_units > 1 ? (
    var.apim_sku_units == 2 ? ["1", "2"] : ["1", "2", "3"]
  ) : []

  # Integrations
  eventhub_namespace_name       = module.eventhub.namespace_name
  eventhub_endpoint_uri         = module.eventhub.endpoint_uri
  eventhub_usage_hub_name       = module.eventhub.apim_usage_hub_name
  eventhub_pii_hub_name         = module.eventhub.pii_usage_hub_name
  cosmos_db_endpoint            = module.cosmosdb.endpoint
  pii_service_endpoint          = var.enable_pii_redaction ? module.foundry.primary_foundry_endpoint : ""
  content_safety_endpoint       = var.enable_content_safety ? module.foundry.primary_foundry_endpoint : ""
  enable_pii_redaction          = var.enable_pii_redaction
  enable_content_safety         = var.enable_content_safety

  # Universal LLM API inference contract (Bicep: inferenceAPIType)
  inference_api_type = var.inference_api_type

  # Auth
  entra_auth_enabled = var.entra_auth_enabled
  entra_tenant_id    = var.entra_tenant_id
  entra_client_id    = var.entra_client_id
  entra_audience     = var.entra_audience

  # Logging
  log_analytics_id = module.monitoring.log_analytics_id
  log_verbosity    = var.apim_log_verbosity
  log_body_bytes   = var.apim_log_body_bytes

  # DNS
  dns_zone_id_apim = module.networking.dns_zone_ids["apim_gateway"]

  # APIM logic plane (§19.12 — Bicep parity for llm-backends/pools, fragments,
  # extra APIs, MCP, API Center onboarding)
  llm_backend_config         = local.effective_llm_backend_config
  configure_circuit_breaker  = var.configure_circuit_breaker
  ai_search_instances        = [for s in var.ai_search_instances : { name = s.name, url = s.endpoint, description = "AI Search backend" }]
  enable_azure_ai_search     = var.enable_azure_ai_search
  enable_embeddings_backend  = var.enable_embeddings_backend
  embeddings_backend_url     = var.embeddings_backend_url
  enable_pii_anonymization   = var.enable_pii_anonymization
  enable_unified_ai_api      = var.enable_unified_ai_api
  enable_ai_model_inference  = var.enable_ai_model_inference
  enable_document_intelligence = var.enable_document_intelligence
  enable_openai_realtime     = var.enable_openai_realtime
  is_mcp_sample_deployed     = var.is_mcp_sample_deployed
  ms_learn_mcp_backend_url   = var.ms_learn_mcp_backend_url

  enable_jwt_auth            = local.effective_enable_jwt_auth
  jwt_tenant_id              = local.effective_jwt_tenant_id
  jwt_app_registration_id    = local.effective_jwt_app_registration_id
  pii_service_key            = var.pii_service_key
  subscription_id            = data.azurerm_client_config.current.subscription_id
  azure_login_endpoint       = var.azure_login_endpoint

  enable_api_center_onboarding     = var.enable_api_center && var.enable_api_center_onboarding
  api_center_service_name          = var.enable_api_center ? module.apic.api_center_name : ""
  api_center_workspace_name        = "default"
  api_center_environment_name      = "api-dev"
  api_center_mcp_environment_name  = "mcp-dev"

  enable_foundry_apim_connection = var.enable_foundry_apim_connection

  depends_on = [module.networking, module.monitoring, module.eventhub, module.cosmosdb, module.redis, module.apic]
}

# =============================================================================
# MODULE: LOGIC APP (Usage Ingestion)
# =============================================================================

module "logic_app" {
  source = "./modules/logic-app"

  resource_group_name = local.resource_group_name_resolved
  location            = var.location
  tags                = local.all_tags
  environment_name    = var.environment_name
  random_suffix       = random_string.suffix.result

  sku_tier = var.logic_app_sku_tier
  sku_size = var.logic_app_sku_size

  # Networking
  subnet_id     = module.networking.logic_app_subnet_id
  pe_subnet_id  = module.networking.pe_subnet_id

  dns_zone_id_blob  = module.networking.dns_zone_ids["storage_blob"]
  dns_zone_id_file  = module.networking.dns_zone_ids["storage_file"]
  dns_zone_id_table = module.networking.dns_zone_ids["storage_table"]
  dns_zone_id_queue = module.networking.dns_zone_ids["storage_queue"]

  # Integrations
  eventhub_endpoint_host        = "${module.eventhub.namespace_name}.servicebus.windows.net"
  eventhub_namespace_name       = module.eventhub.namespace_name
  eventhub_ai_usage_hub_name    = module.eventhub.apim_usage_hub_name
  eventhub_pii_usage_hub_name   = module.eventhub.pii_usage_hub_name

  cosmos_db_endpoint                   = module.cosmosdb.endpoint
  cosmos_db_account_name               = module.cosmosdb.account_name
  cosmos_db_account_id                 = module.cosmosdb.account_id
  cosmos_db_connection_string    = module.cosmosdb.connection_string

  # cosmos container names
  cosmos_db_database_name = module.cosmosdb.database_name
  cosmos_db_container_config = module.cosmosdb.config_container_name
  cosmos_db_container_usage  = module.cosmosdb.usage_container_name
  cosmos_db_container_pii    = module.cosmosdb.pii_container_name
  cosmos_db_container_llm_usage = module.cosmosdb.llm_usage_container_name

  app_insights_connection_string = module.monitoring.app_insights_connection_string
  apim_app_insights_name         = module.monitoring.app_insights_name
  apim_app_insights_rg           = local.resource_group_name_resolved
  subscription_id                = var.subscription_id

  content_share_name = var.logic_content_share_name

  # Workflow-code publish. Defaults to the
  # vendored accelerator project under logicapp-src/usage-ingestion-logicapp.
  enable_code_deploy = var.enable_logic_app_code_deploy
  code_source_path = var.logic_app_code_source_path != "" ? var.logic_app_code_source_path : "${path.root}/logicapp-src/usage-ingestion-logicapp"

  # Identity (Logic App uses the usage UAMI per Bicep managed-identity-usage.bicep)
  managed_identity_id           = local.usage_identity_id
  managed_identity_client_id    = local.usage_identity_client_id
  managed_identity_principal_id = local.usage_identity_principal

  depends_on = [module.eventhub, module.cosmosdb]

  log_analytics_id = module.monitoring.log_analytics_id
}
