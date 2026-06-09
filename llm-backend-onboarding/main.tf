# =============================================================================
# LLM Backend Onboarding — Main
#
# Standalone Terraform deployment for onboarding LLM backends to an existing
# APIM instance. Creates:
#   1. Individual APIM backends (one per LLM endpoint)
#   2. Backend pools (load-balanced groups for models with multiple backends)
#   3. Policy fragments (dynamic routing logic)
#
# This mirrors the Bicep llm-backend-onboarding module but as a standalone
# Terraform root module that can be applied independently.
# =============================================================================

# -----------------------------------------------------------------------------
# DATA SOURCES — Reference existing APIM
# -----------------------------------------------------------------------------

data "azurerm_api_management" "citadel" {
  name                = var.apim_name
  resource_group_name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# LOCALS — Pool grouping logic (mirrors modules/apim/backends.tf)
# -----------------------------------------------------------------------------

locals {
  # Normalize LLM backends — extract per-model name lists for pool grouping.
  llm_backends_normalized = [
    for b in var.llm_backend_config : {
      backend_id   = b.backend_id
      backend_type = b.backend_type
      endpoint     = b.endpoint
      auth_scheme  = b.auth_scheme
      priority     = b.priority
      weight       = b.weight
      model_names  = [for m in b.supported_models : m.name]
      # Bicep parity: pool entries carry authType + authConfigNamedValue.
      # Coalesce to "" because `try` only catches missing keys, not explicit
      # nulls — a null here breaks the C# code-gen string templates.
      auth_type               = try(b.auth_type, "") == null ? "" : try(b.auth_type, "")
      auth_config_named_value = try(b.auth_config.named_value_key, "") == null ? "" : try(b.auth_config.named_value_key, "")
    }
  ]

  # Flatten model → backends map so each model lists the backends that serve it.
  model_to_backends_pairs = flatten([
    for b in local.llm_backends_normalized : [
      for m in b.model_names : {
        model        = m
        backend_id   = b.backend_id
        backend_type = b.backend_type
        priority     = b.priority
        weight       = b.weight
        auth_type               = b.auth_type
        auth_config_named_value = b.auth_config_named_value
      }
    ]
  ])

  # Group by model name into a map of lists.
  model_to_backends = {
    for m in distinct([for p in local.model_to_backends_pairs : p.model]) :
    m => [for p in local.model_to_backends_pairs : p if p.model == m]
  }

  # Pools: only models served by 2+ backends get a pool.
  pool_configs = {
    for m, backends in local.model_to_backends :
    "${replace(m, ".", "")}-backend-pool" => {
      model_name = m
      backends   = backends
    } if length(backends) > 1
  }

  # Direct backends: models served by exactly 1 backend.
  direct_backends = {
    for m, backends in local.model_to_backends :
    m => backends[0] if length(backends) == 1
  }

  # Unified "allPools" list that the C#-code-gen fragments consume.
  all_pools = concat(
    [for pool_name, cfg in local.pool_configs : {
      pool_name        = pool_name
      pool_type        = length(cfg.backends) > 0 ? cfg.backends[0].backend_type : "mixed"
      supported_models = [cfg.model_name]
      auth_type               = length(cfg.backends) > 0 ? cfg.backends[0].auth_type : ""
      auth_config_named_value = length(cfg.backends) > 0 ? cfg.backends[0].auth_config_named_value : ""
    }],
    [for model_name, b in local.direct_backends : {
      pool_name        = b.backend_id
      pool_type        = b.backend_type
      supported_models = [model_name]
      auth_type               = b.auth_type
      auth_config_named_value = b.auth_config_named_value
    }]
  )
}

# -----------------------------------------------------------------------------
# LLM BACKENDS (one per endpoint)
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend" {
  for_each = { for b in var.llm_backend_config : b.backend_id => b }

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.value.backend_id
  parent_id = data.azurerm_api_management.citadel.id

  # credentials.managedIdentity is not in the embedded azapi schema for this
  # api-version; disable validation (matches modules/apim/backends.tf).
  schema_validation_enabled = false

  body = {
    properties = {
      description = "LLM Backend: ${each.value.backend_type} - ${each.value.backend_id} - Supports models: ${join(", ", [for m in each.value.supported_models : m.name])}"
      url         = each.value.endpoint
      protocol    = "http"

      circuitBreaker = var.configure_circuit_breaker ? {
        rules = [{
          failureCondition = {
            count        = 3
            errorReasons = ["Server errors"]
            interval     = "PT5M"
            statusCodeRanges = [
              { min = 429, max = 429 },
              { min = 500, max = 503 }
            ]
          }
          name             = "${each.value.backend_id}-breaker-rule"
          tripDuration     = "PT1M"
          acceptRetryAfter = true
        }]
      } : null

      # Native APIM backend managed-identity credential (Bicep parity:
      # llm-backends.bicep credentials.managedIdentity). The x-ms-client-id
      # header is preserved for backends that key on it. Non-managed-identity
      # auth schemes are handled in policy fragments, so both keys are null.
      credentials = {
        managedIdentity = each.value.auth_scheme == "managedIdentity" ? {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        } : null
        header = each.value.auth_scheme == "managedIdentity" ? {
          "x-ms-client-id" = [var.managed_identity_client_id]
        } : null
      }

      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }
}

# -----------------------------------------------------------------------------
# LLM BACKEND POOLS (load balancer — models with 2+ backends)
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend_pool" {
  for_each = local.pool_configs

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.key
  parent_id = data.azurerm_api_management.citadel.id

  body = {
    properties = {
      description = "Backend pool for model: ${each.value.model_name}"
      type        = "Pool"
      pool = {
        services = [for b in each.value.backends : {
          id       = "/backends/${b.backend_id}"
          priority = b.priority
          weight   = b.weight
        }]
      }
    }
  }

  depends_on = [azapi_resource.llm_backend]
}

# -----------------------------------------------------------------------------
# POLICY FRAGMENTS — Dynamic code generation
# -----------------------------------------------------------------------------

locals {
  # -- set-backend-pools: per-pool C# JObject blocks (Bicep parity: include
  #    authType + authConfigNamedValue for per-pool credential resolution).
  backend_pools_code = join("\n", [
    for idx, pool in local.all_pools : join("\n", [
      "// Pool: ${pool.pool_name} (Type: ${pool.pool_type}, Auth: ${pool.auth_type})",
      "var pool_${idx} = new JObject()",
      "{",
      "    { \"poolName\", \"${pool.pool_name}\" },",
      "    { \"poolType\", \"${pool.pool_type}\" },",
      "    { \"authType\", \"${pool.auth_type}\" },",
      "    { \"authConfigNamedValue\", \"${pool.auth_config_named_value}\" },",
      "    { \"supportedModels\", new JArray(${join(", ", [for m in pool.supported_models : "\"${m}\""])}) }",
      "};",
      "backendPools.Add(pool_${idx});"
    ])
  ])

  # -- get-available-models: per-model C# JObject blocks
  flattened_models = flatten([
    for b in var.llm_backend_config : [
      for m in b.supported_models : {
        backend_id      = b.backend_id
        backend_type    = b.backend_type
        name            = m.name
        sku             = m.sku
        capacity        = m.capacity
        modelFormat     = m.modelFormat
        modelVersion    = m.modelVersion
        retirement_date = m.retirementDate
      }
    ]
  ])

  model_deployments_code = join("\n", [
    for idx, m in local.flattened_models : join("\n", [
      "// Model: ${m.name} from backend: ${m.backend_id}",
      "var deployment_${idx} = new JObject()",
      "{",
      "    { \"id\", \"${m.backend_id}\" },",
      "    { \"type\", \"${m.backend_type}\" },",
      "    { \"name\", \"${m.name}\" },",
      "    { \"sku\", new JObject() { { \"name\", \"${m.sku}\" }, { \"capacity\", ${m.capacity} } } },",
      "    { \"properties\", new JObject() {",
      "        { \"model\", new JObject() { { \"format\", \"${m.modelFormat}\" }, { \"name\", \"${m.name}\" }, { \"version\", \"${m.modelVersion}\" } } },",
      "        { \"capabilities\", new JObject() { { \"chatCompletion\", \"true\" } } },",
      "        { \"provisioningState\", \"Succeeded\" }${m.retirement_date != "" ? ",\n        { \"retirementDate\", \"${m.retirement_date}\" }" : ""}",
      "    }}",
      "};",
      "modelDeployments.Add(deployment_${idx});"
    ])
  ])

  # -- metadata-config: per-unique-model mapping (first seen wins)
  metadata_models = [
    for model_name in distinct([for m in local.flattened_models : m.name]) : {
      name      = model_name
      pool_name = try([for p in local.all_pools : p.pool_name if contains(p.supported_models, model_name)][0], "")
      apiVersion = try([
        for b in var.llm_backend_config : [
          for mm in b.supported_models : mm.apiVersion if mm.name == model_name
        ]
      ][0][0], "2024-02-15-preview")
      timeout = try([
        for b in var.llm_backend_config : [
          for mm in b.supported_models : mm.timeout if mm.name == model_name
        ]
      ][0][0], 120)
      inferenceApiVersion = try([
        for b in var.llm_backend_config : [
          for mm in b.supported_models : mm.inferenceApiVersion if mm.name == model_name
        ]
      ][0][0], "")
    }
  ]

  metadata_models_code = join(",\n", [
    for m in local.metadata_models :
    "\t\t\t'${m.name}': {\n\t\t\t\t'backend': '${m.pool_name}',\n\t\t\t\t'apiVersion': '${m.apiVersion}',\n\t\t\t\t'timeout': ${m.timeout}${m.inferenceApiVersion != "" ? ",\n\t\t\t\t'inferenceApiVersion': '${m.inferenceApiVersion}'" : ""}\n\t\t\t}"
  ])

  # Final XML contents for the 3 dynamic fragments
  set_backend_pools_xml = replace(
    file("${path.module}/policies/frag-set-backend-pools.xml"),
    "//{backendPoolsCode}",
    local.backend_pools_code
  )

  get_available_models_xml = replace(
    file("${path.module}/policies/frag-get-available-models.xml"),
    "//{modelDeploymentsCode}",
    local.model_deployments_with_aliases_code
  )

  # -- Alias discovery entries (Bicep parity: aliasDeploymentEntries). Appended to
  #    the model-deployments JArray so aliases surface in /deployments discovery.
  alias_deployments_code = join("\n", [
    for i, a in var.model_aliases : join("\n", [
      "// Alias: ${a.name}",
      "var aliasDeployment_${i} = new JObject()",
      "{",
      "    { \"id\", \"alias\" },",
      "    { \"type\", \"alias\" },",
      "    { \"name\", \"${a.name}\" },",
      "    { \"sku\", new JObject() { { \"name\", \"Standard\" }, { \"capacity\", 100 } } },",
      "    { \"properties\", new JObject() {",
      "        { \"model\", new JObject() { { \"format\", \"Alias\" }, { \"name\", \"${a.name}\" }, { \"version\", \"1\" } } },",
      "        { \"capabilities\", new JObject() { { \"chatCompletion\", \"true\" }, { \"description\", \"Alias for: ${join(", ", a.models)} (strategy: ${a.strategy}${length(a.weights) > 0 ? "; weights: ${join(", ", a.weights)}" : ""})\" } } },",
      "        { \"provisioningState\", \"Succeeded\" }",
      "    }}",
      "};",
      "modelDeployments.Add(aliasDeployment_${i});"
    ])
  ])

  model_deployments_with_aliases_code = "${local.model_deployments_code}${length(var.model_aliases) > 0 ? "\n${local.alias_deployments_code}" : ""}"

  # -- resolve-model-alias: C# JObject style (injected into //{inlineAliasesCode}).
  inline_aliases_code = join("\n", [
    for a in var.model_aliases :
    "            { \"${a.name}\", new JObject { { \"strategy\", \"${a.strategy}\" }, { \"models\", new JArray(${join(", ", [for m in a.models : "\"${m}\""])}) }${length(a.weights) > 0 ? ", { \"weights\", new JArray(${join(", ", a.weights)}) }" : ""} } },"
  ])

  # -- metadata-config: JS object-literal style (injected into //{modelAliasesCode}
  #    which sits inside the 'model-aliases': { ... } JS block, NOT C# code).
  metadata_aliases_code = join(",\n", [
    for a in var.model_aliases :
    "\t\t\t'${a.name}': {\n\t\t\t\t'models': [${join(", ", [for m in a.models : "'${m}'"])}],\n\t\t\t\t'strategy': '${a.strategy}'${length(a.weights) > 0 ? ",\n\t\t\t\t'weights': [${join(", ", a.weights)}]" : ""}\n\t\t\t}"
  ])

  metadata_config_xml_1 = replace(
    file("${path.module}/policies/frag-metadata-config.xml"),
    "//{modelsConfigCode}",
    local.metadata_models_code
  )
  metadata_config_xml = replace(
    local.metadata_config_xml_1,
    "//{modelAliasesCode}",
    local.metadata_aliases_code
  )
}

# -----------------------------------------------------------------------------
# Dynamic Policy Fragments (3 — generated C# injected into XML templates)
# -----------------------------------------------------------------------------

resource "azurerm_api_management_policy_fragment" "set_backend_pools" {
  api_management_id = data.azurerm_api_management.citadel.id
  name              = "set-backend-pools"
  format            = "rawxml"
  description       = "Dynamically generated backend pool configurations for LLM routing"
  value             = local.set_backend_pools_xml
}

resource "azurerm_api_management_policy_fragment" "get_available_models" {
  api_management_id = data.azurerm_api_management.citadel.id
  name              = "get-available-models"
  format            = "rawxml"
  description       = "Returns available model deployments"
  value             = local.get_available_models_xml
}

resource "azurerm_api_management_policy_fragment" "metadata_config" {
  api_management_id = data.azurerm_api_management.citadel.id
  name              = "metadata-config"
  format            = "rawxml"
  description       = "Dynamically generated metadata configuration for Unified AI API routing"
  value             = local.metadata_config_xml
}

# -----------------------------------------------------------------------------
# Static Policy Fragments
# -----------------------------------------------------------------------------

locals {
  static_fragments = {
    "set-backend-authorization" = {
      description = "Authentication and routing configuration for different LLM backend types"
      file        = "frag-set-backend-authorization.xml"
    }
    "set-target-backend-pool" = {
      description = "Determines the target backend pool for LLM requests"
      file        = "frag-set-target-backend-pool.xml"
    }
    "set-llm-requested-model" = {
      description = "Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)"
      file        = "frag-set-llm-requested-model.xml"
    }
    "set-llm-usage" = {
      description = "Collects usage metrics for LLM requests"
      file        = "frag-set-llm-usage.xml"
    }
    "validate-model-access" = {
      description = "Validates the caller is permitted to access the requested model"
      file        = "frag-validate-model-access.xml"
    }
    "responses-id-security" = {
      description = "Enforces tenant isolation for Responses API response IDs"
      file        = "frag-responses-id-security.xml"
    }
    "responses-id-cache-store" = {
      description = "Stores Responses API response-ID to tenant mapping in cache"
      file        = "frag-responses-id-cache-store.xml"
    }
  }
}

resource "azurerm_api_management_policy_fragment" "static" {
  for_each = local.static_fragments

  api_management_id = data.azurerm_api_management.citadel.id
  name              = each.key
  format            = "rawxml"
  description       = each.value.description
  value             = file("${path.module}/policies/${each.value.file}")

  depends_on = [
    azurerm_api_management_named_value.aws_access_key,
    azurerm_api_management_named_value.aws_secret_key,
    azurerm_api_management_named_value.aws_region,
    azurerm_api_management_named_value.backend_api_key,
  ]

  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
  }
}


resource "azurerm_api_management_policy_fragment" "resolve_model_alias" {
  api_management_id = data.azurerm_api_management.citadel.id
  name              = "resolve-model-alias"
  format            = "rawxml"
  description       = "Resolves model alias names to actual underlying models"
  value = replace(
    file("${path.module}/policies/frag-resolve-model-alias.xml"),
    "//{inlineAliasesCode}",
    local.inline_aliases_code
  )
}

# -----------------------------------------------------------------------------
# Named Values — AWS Bedrock auth + dynamic backend API-key credentials
# (Bicep parity: llm-policy-fragments.bicep aws-* + backendApiKeyNamedValues)
# -----------------------------------------------------------------------------

# Always created with safe defaults so the set-backend-authorization fragment
# compiles even when no aws-bedrock backends are configured.
resource "azurerm_api_management_named_value" "aws_access_key" {
  name                = "aws-access-key"
  resource_group_name = data.azurerm_api_management.citadel.resource_group_name
  api_management_name = data.azurerm_api_management.citadel.name
  display_name        = "aws-access-key"
  value               = var.aws_access_key != "" ? var.aws_access_key : "NOT_CONFIGURED"
  secret              = true
}

resource "azurerm_api_management_named_value" "aws_secret_key" {
  name                = "aws-secret-key"
  resource_group_name = data.azurerm_api_management.citadel.resource_group_name
  api_management_name = data.azurerm_api_management.citadel.name
  display_name        = "aws-secret-key"
  value               = var.aws_secret_key != "" ? var.aws_secret_key : "NOT_CONFIGURED"
  secret              = true
}

resource "azurerm_api_management_named_value" "aws_region" {
  name                = "aws-region"
  resource_group_name = data.azurerm_api_management.citadel.resource_group_name
  api_management_name = data.azurerm_api_management.citadel.name
  display_name        = "aws-region"
  value               = var.aws_region != "" ? var.aws_region : "NOT_CONFIGURED"
  secret              = false
}

# Dynamic named values for backend API-key credentials. Backends with
# auth_config.named_value_key use a Key Vault reference when key_vault_secret_uri
# is supplied, otherwise an explicit value (testing only).
locals {
  backend_auth_named_values = {
    for b in var.llm_backend_config :
    b.auth_config.named_value_key => {
      key_vault_secret_uri = try(b.auth_config.key_vault_secret_uri, "")
      secret_value         = try(b.auth_config.secret_value, "")
    }
    if try(b.auth_config.named_value_key, "") != ""
  }
}

resource "azurerm_api_management_named_value" "backend_api_key" {
  for_each = local.backend_auth_named_values

  name                = each.key
  resource_group_name = data.azurerm_api_management.citadel.resource_group_name
  api_management_name = data.azurerm_api_management.citadel.name
  display_name        = each.key
  secret              = true

  # Use Key Vault reference if a secret URI is provided, otherwise explicit value.
  value = each.value.key_vault_secret_uri == "" ? (each.value.secret_value != "" ? each.value.secret_value : "NOT_CONFIGURED") : null

  dynamic "value_from_key_vault" {
    for_each = each.value.key_vault_secret_uri != "" ? [1] : []
    content {
      secret_id = each.value.key_vault_secret_uri
    }
  }
}