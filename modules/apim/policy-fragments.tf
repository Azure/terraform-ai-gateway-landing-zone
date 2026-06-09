# =============================================================================
# APIM POLICY FRAGMENTS — Bicep parity:
#   llm-policy-fragments.bicep (8 fragments, 3 with dynamic C# code)
#   policy-fragments.bicep (11 fragments, all static)
#
# Dynamic fragments are built by locally generating the embedded C# / JSON
# blocks and injecting them into the XML with `replace()`.
#
# NOTE — PII fragments: previously managed under
# `azurerm_api_management_policy_fragment.static[...]` but that resource has
# a known LRO polling bug ("404 Not Found: PolicyFragment not found" during
# `CreateOrUpdate` poll). PII fragments are now managed via `azapi_resource`
# below (direct idempotent PUT). If any of `pii-anonymization` /
# `pii-deanonymization` / `pii-state-saving` are in state under the old
# azurerm address, drop them without destroying before running apply:
#
#   terraform state rm \
#     'module.apim.azurerm_api_management_policy_fragment.static["pii-deanonymization"]' \
#     'module.apim.azurerm_api_management_policy_fragment.static["pii-state-saving"]'
#
# (scripts/migrate-pii-fragments.sh automates this.)
# =============================================================================

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
    }
  ]

  metadata_models_code = join(",\n", [
    for m in local.metadata_models :
    "\t\t\t'${m.name}': {\n\t\t\t\t'backend': '${m.pool_name}',\n\t\t\t\t'apiVersion': '${m.apiVersion}',\n\t\t\t\t'timeout': ${m.timeout}\n\t\t\t}"
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
# Static fragments — llm-policy-fragments.bicep + policy-fragments.bicep
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
    "set-llm-usage" = {
      description = "Collects usage metrics for LLM requests"
      file        = "frag-set-llm-usage.xml"
    }
    "set-llm-requested-model" = {
      description = "Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)"
      file        = "frag-set-llm-requested-model.xml"
    }
    "validate-model-access" = {
      description = "Validates that the requested model is in the allowed models list for the product"
      file        = "frag-validate-model-access.xml"
    }
    "ai-usage" = {
      description = "Tracks usage of all AI-related APIs"
      file        = "frag-ai-usage.xml"
    }
    "raise-throttling-events" = {
      description = "Raises custom events when throttling limits are hit"
      file        = "frag-raise-throttling-events.xml"
    }
    "throttling-events" = {
      description = "Throttling events configuration"
      file        = "frag-throttling-events.xml"
    }
    "security-handler" = {
      description = "Unified authentication handler for all AI Gateway APIs"
      file        = "frag-security-handler.xml"
    }
    "entra-auth" = {
      description = "Entra ID authentication fragment"
      file        = "frag-entra-auth.xml"
    }
    "aad-auth" = {
      description = "AAD auth fragment"
      file        = "frag-aad-auth.xml"
    }
    "aad-auth-custom" = {
      description = "AAD auth (custom) fragment"
      file        = "frag-aad-auth-custom.xml"
    }
    "ai-foundry-deployments" = {
      description = "AI Foundry deployments helper fragment"
      file        = "frag-ai-foundry-deployments.xml"
    }
    "llm-usage" = {
      description = "LLM usage tracking"
      file        = "frag-llm-usage.xml"
    }
    "openai-usage" = {
      description = "OpenAI usage tracking"
      file        = "frag-openai-usage.xml"
    }
    "openai-usage-streaming" = {
      description = "OpenAI streaming usage tracking"
      file        = "frag-openai-usage-streaming.xml"
    }
    # Referenced unconditionally by universal-llm-api-policy-v2.xml and
    # azure-open-ai-api-policy.xml, so must always be created even when the
    # PII / Unified AI feature flags are off.
    "ai-foundry-compatibility" = {
      description = "Foundry CORS compatibility"
      file        = "frag-ai-foundry-compatibility.xml"
    }
    "set-response-headers" = {
      description = "Adds UAIG-* response headers"
      file        = "frag-set-response-headers.xml"
    }
    "responses-id-security" = {
      description = "Per-subscription ownership enforcement for the Responses API"
      file        = "frag-responses-id-security.xml"
    }
    "responses-id-cache-store" = {
      description = "Records ownership of newly created Responses API objects"
      file        = "frag-responses-id-cache-store.xml"
    }
    "strip-backend-headers" = {
      description = "Removes browser, App Service/ARR, and X-Forwarded-* headers before forwarding to AI backends"
      file        = "frag-strip-backend-headers.xml"
    }
  }

  pii_fragments = var.enable_pii_anonymization ? {
    "pii-anonymization" = {
      description = "Anonymizes PII in API requests"
      file        = "frag-pii-anonymization.xml"
    }
    "pii-deanonymization" = {
      description = "Deanonymizes PII in API responses"
      file        = "frag-pii-deanonymization.xml"
    }
    "pii-state-saving" = {
      description = "Saves PII state for testing"
      file        = "frag-pii-state-saving.xml"
    }
  } : {}

  unified_ai_fragments = var.enable_unified_ai_api ? {
    "central-cache-manager" = {
      description = "Caches metadata configuration for Unified AI API"
      file        = "frag-central-cache-manager.xml"
    }
    "request-processor" = {
      description = "Analyzes incoming Unified AI requests"
      file        = "frag-request-processor.xml"
    }
    "path-builder" = {
      description = "Reconstructs backend URI paths for Unified AI API"
      file        = "frag-path-builder.xml"
    }
  } : {}

  all_static_fragments = merge(local.static_fragments, local.unified_ai_fragments)
}

resource "azurerm_api_management_policy_fragment" "static" {
  for_each = local.all_static_fragments

  api_management_id = azurerm_api_management.citadel.id
  name              = each.key
  format            = "rawxml"
  description       = each.value.description
  value             = file("${path.module}/policies/${each.value.file}")

  # APIM's CreateOrUpdate LRO intermittently returns 404 ResourceNotFound on
  # the status endpoint before the fragment is queryable (eventual consistency
  # on the control plane). Give the provider enough time to keep polling
  # instead of failing on the first 404.
  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
  }

  # APIM validates named-value references at create time; ensure all named
  # values the fragments depend on exist first.
  depends_on = [
    azurerm_api_management_named_value.uami_client_id,
    azurerm_api_management_named_value.entra_tenant_id,
    azurerm_api_management_named_value.entra_client_id,
    azurerm_api_management_named_value.entra_audience,
    azurerm_api_management_named_value.entra_auth_flag,
    azurerm_api_management_named_value.pii_service_url,
    azurerm_api_management_named_value.content_safety_url,
    azurerm_api_management_named_value.jwt_tenant_id,
    azurerm_api_management_named_value.jwt_app_registration_id,
    azurerm_api_management_named_value.jwt_issuer,
    azurerm_api_management_named_value.jwt_openid_config_url,
    azurerm_api_management_named_value.pii_service_key,
  ]
}

# -----------------------------------------------------------------------------
# Dynamic fragments (3) — generated C# injected into XML templates.
# Always created (even with empty llm_backend_config) because the
# universal-llm-api / azure-openai-api / unified-ai-api policies reference
# them unconditionally and APIM validates fragment IDs at policy save time.
# -----------------------------------------------------------------------------

resource "azurerm_api_management_policy_fragment" "set_backend_pools" {
  api_management_id = azurerm_api_management.citadel.id
  name              = "set-backend-pools"
  format            = "rawxml"
  description       = "Dynamically generated backend pool configurations for LLM routing"
  value             = local.set_backend_pools_xml
}

resource "azurerm_api_management_policy_fragment" "get_available_models" {
  api_management_id = azurerm_api_management.citadel.id
  name              = "get-available-models"
  format            = "rawxml"
  description       = "Returns available model deployments"
  value             = local.get_available_models_xml
}

resource "azurerm_api_management_policy_fragment" "metadata_config" {
  api_management_id = azurerm_api_management.citadel.id
  name              = "metadata-config"
  format            = "rawxml"
  description       = "Dynamically generated metadata configuration for Unified AI API routing"
  value             = local.metadata_config_xml
}

resource "azurerm_api_management_policy_fragment" "resolve_model_alias" {
  api_management_id = azurerm_api_management.citadel.id
  name              = "resolve-model-alias"
  format            = "rawxml"
  description       = "Resolves model alias names to actual underlying models with priority/weighted strategy"
  value = replace(
    file("${path.module}/policies/frag-resolve-model-alias.xml"),
    "//{inlineAliasesCode}",
    local.inline_aliases_code
  )
}

# -----------------------------------------------------------------------------
# PII policy fragments — managed via `azapi_resource` to bypass a known
# azurerm provider bug where `azurerm_api_management_policy_fragment` fails
# `CreateOrUpdate` with "polling after CreateOrUpdate: ... 404 Not Found:
# PolicyFragment not found" because APIM's LRO status endpoint returns a
# transient 404 before the fragment is queryable. azapi performs a direct
# idempotent PUT and does not rely on that flaky LRO poller, so it works
# reliably for the same fragments that fail under azurerm.
# -----------------------------------------------------------------------------

resource "azapi_resource" "pii_fragment" {
  for_each = local.pii_fragments

  type      = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  name      = each.key
  parent_id = azurerm_api_management.citadel.id

  body = {
    properties = {
      value       = file("${path.module}/policies/${each.value.file}")
      format      = "rawxml"
      description = each.value.description
    }
  }

  # PUTs of policy fragments can take a while when APIM is updating other
  # resources in parallel; give it room.
  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
  }

  # Same named-value dependency chain as the azurerm static fragments.
  depends_on = [
    azurerm_api_management_named_value.uami_client_id,
    azurerm_api_management_named_value.pii_service_url,
    azurerm_api_management_named_value.pii_service_key,
  ]
}
