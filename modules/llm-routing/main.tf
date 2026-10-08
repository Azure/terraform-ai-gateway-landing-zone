# =============================================================================
# LLM ROUTING — turns the LLM backend catalogue into APIM backends, backend
# pools (load balancing + circuit breaker) and the four generated routing
# fragments (set-backend-pools, get-available-models, metadata-config,
# resolve-model-alias). Bicep parity: llm-backends.bicep, llm-backend-pools.bicep,
# llm-policy-fragments.bicep (dynamic part). Moved from modules/apim (Phase 1).
# =============================================================================

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
      # Bicep parity: pool entries carry authType + authConfigNamedValue so the
      # set-backend-pools fragment can resolve per-pool credentials.
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
        model                   = m
        backend_id              = b.backend_id
        backend_type            = b.backend_type
        priority                = b.priority
        weight                  = b.weight
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
      pool_name               = pool_name
      pool_type               = length(cfg.backends) > 0 ? cfg.backends[0].backend_type : "mixed"
      supported_models        = [cfg.model_name]
      auth_type               = length(cfg.backends) > 0 ? cfg.backends[0].auth_type : ""
      auth_config_named_value = length(cfg.backends) > 0 ? cfg.backends[0].auth_config_named_value : ""
    }],
    [for model_name, b in local.direct_backends : {
      pool_name               = b.backend_id
      pool_type               = b.backend_type
      supported_models        = [model_name]
      auth_type               = b.auth_type
      auth_config_named_value = b.auth_config_named_value
    }]
  )
}

# -----------------------------------------------------------------------------
# LLM BACKENDS (one per endpoint) — llm-backends.bicep
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend" {
  for_each = { for b in var.llm_backend_config : b.backend_id => b }

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.value.backend_id
  parent_id = var.api_management_id

  # credentials.managedIdentity is not in the embedded azapi schema for this
  # api-version; disable validation (same as content_safety/embeddings backends).
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
# LLM BACKEND POOLS (load balancer) — llm-backend-pools.bicep
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend_pool" {
  for_each = local.pool_configs

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.key
  parent_id = var.api_management_id

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
# Dynamic code generation (mirrors Bicep reduce/map over llmBackendConfig)
# -----------------------------------------------------------------------------

locals {
  # -- set-backend-pools: per-pool C# JObject blocks (Bicep parity: pool entries
  #    include authType + authConfigNamedValue so credentials resolve per pool).
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
    file("${path.module}/templates/frag-set-backend-pools.xml"),
    "//{backendPoolsCode}",
    local.backend_pools_code
  )

  get_available_models_xml = replace(
    file("${path.module}/templates/frag-get-available-models.xml"),
    "//{modelDeploymentsCode}",
    local.model_deployments_with_aliases_code
  )

  # -- Alias discovery entries (Bicep parity: aliasDeploymentEntries). Each alias
  #    is appended to the model-deployments JArray so it appears in /deployments
  #    discovery alongside real models; allowedModels filtering treats them
  #    identically, so RBAC extends to aliases automatically.
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
    file("${path.module}/templates/frag-metadata-config.xml"),
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
# Dynamic fragments (3) — generated C# injected into XML templates.
# Always created (even with empty llm_backend_config) because the
# universal-llm-api / azure-openai-api / unified-ai-api policies reference
# them unconditionally and APIM validates fragment IDs at policy save time.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_policy_fragment" "set_backend_pools" {
  api_management_id = var.api_management_id
  name              = "set-backend-pools"
  format            = "rawxml"
  description       = "Dynamically generated backend pool configurations for LLM routing"
  value             = local.set_backend_pools_xml
}

resource "azurerm_api_management_policy_fragment" "get_available_models" {
  api_management_id = var.api_management_id
  name              = "get-available-models"
  format            = "rawxml"
  description       = "Returns available model deployments"
  value             = local.get_available_models_xml
}

resource "azurerm_api_management_policy_fragment" "metadata_config" {
  api_management_id = var.api_management_id
  name              = "metadata-config"
  format            = "rawxml"
  description       = "Dynamically generated metadata configuration for Unified AI API routing"
  value             = local.metadata_config_xml
}

resource "azurerm_api_management_policy_fragment" "resolve_model_alias" {
  api_management_id = var.api_management_id
  name              = "resolve-model-alias"
  format            = "rawxml"
  description       = "Resolves model alias names to actual underlying models with priority/weighted strategy"
  value = replace(
    file("${path.module}/templates/frag-resolve-model-alias.xml"),
    "//{inlineAliasesCode}",
    local.inline_aliases_code
  )
}

