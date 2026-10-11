# =============================================================================
# LLM ROUTING — turns the LLM backend catalogue into APIM backends, backend
# pools (load balancing + circuit breaker) and the four generated routing
# fragments (set-backend-pools, get-available-models, metadata-config,
# resolve-model-alias).
# =============================================================================

locals {
  # Models and pools are keyed by (model, backend type): the same model id served by two
  # different backend types (an aws-bedrock native pool and an aws-bedrock-mantle OpenAI-
  # compatible pool, say) must stay two pools, or the poolType filter of the inbound API
  # surface could not tell them apart. "||" is legal in neither a model id nor a type.
  model_key_delimiter = "||"

  # Normalize LLM backends — extract per-model name lists for pool grouping.
  llm_backends_normalized = [
    for b in var.llm_backend_config : {
      backend_id   = b.backend_id
      backend_type = b.backend_type
      endpoint     = b.endpoint
      priority     = b.priority
      weight       = b.weight
      model_names  = [for m in b.supported_models : m.name]
      # Models this backend flags as session-aware (stateful): their pools get session affinity.
      session_aware_model_names = [for m in b.supported_models : m.name if m.sessionAwareModel]
      session_affinity          = b.session_affinity
      # pool entries carry authType + authConfigNamedValue so the
      # set-backend-pools fragment can resolve per-pool credentials.
      # Coalesce to "" because `try` only catches missing keys, not explicit
      # nulls — a null here breaks the C# code-gen string templates.
      auth_type               = try(b.auth_type, "") == null ? "" : try(b.auth_type, "")
      auth_config_named_value = try(b.auth_config.named_value_key, "") == null ? "" : try(b.auth_config.named_value_key, "")
    }
  ]

  # One row per (backend, model).
  model_to_backends_pairs = flatten([
    for b in local.llm_backends_normalized : [
      for m in b.model_names : {
        key                     = "${m}${local.model_key_delimiter}${b.backend_type}"
        model                   = m
        backend_id              = b.backend_id
        backend_type            = b.backend_type
        priority                = b.priority
        weight                  = b.weight
        auth_type               = b.auth_type
        auth_config_named_value = b.auth_config_named_value
        session_aware           = contains(b.session_aware_model_names, m)
        session_affinity        = b.session_affinity
      }
    ]
  ])

  # Group by (model, backend type) into a map of lists.
  model_to_backends = {
    for k in distinct([for p in local.model_to_backends_pairs : p.key]) :
    k => [for p in local.model_to_backends_pairs : p if p.key == k]
  }

  # Pools: only (model, backend type) combinations served by 2+ backends get a pool. The name
  # strips the characters APIM resource names don't allow (. : _ /) from both parts; the real
  # model id stays the routing key.
  pool_configs = {
    for k, backends in local.model_to_backends :
    "${replace(replace(replace(replace(backends[0].model, ".", ""), ":", ""), "_", ""), "/", "")}-${replace(replace(replace(replace(backends[0].backend_type, ".", ""), ":", ""), "_", ""), "/", "")}-backend-pool" => {
      model_name   = backends[0].model
      backend_type = backends[0].backend_type
      backends     = backends
      # Session affinity (sticky routing) only for pools of a session-aware model, while the
      # master toggle is on: the cookie settings are the defaults overridden by the first
      # pool member that sets its own.
      session_aware = var.session_affinity.enabled && anytrue([for b in backends : b.session_aware])
      session_affinity = {
        cookie_name = try([for b in backends : b.session_affinity.cookie_name if b.session_affinity != null && b.session_affinity.cookie_name != null][0], var.session_affinity.cookie_name)
        source      = try([for b in backends : b.session_affinity.source if b.session_affinity != null && b.session_affinity.source != null][0], var.session_affinity.source)
      }
    } if length(backends) > 1
  }

  # Direct backends: (model, backend type) combinations served by exactly 1 backend.
  direct_backends = {
    for k, backends in local.model_to_backends :
    k => backends[0] if length(backends) == 1
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
    [for k, b in local.direct_backends : {
      pool_name               = b.backend_id
      pool_type               = b.backend_type
      supported_models        = [b.model]
      auth_type               = b.auth_type
      auth_config_named_value = b.auth_config_named_value
    }]
  )
}

# -----------------------------------------------------------------------------
# LLM BACKENDS (one per endpoint)
# -----------------------------------------------------------------------------

locals {
  # Authentication of each backend: the explicit auth_type, else the default of its
  # backend type (the same order the routing fragments use), else managed identity.
  effective_auth_type = {
    for b in var.llm_backend_config : b.backend_id => (
      coalesce(b.auth_type, "-") != "-" ? b.auth_type :
      b.backend_type == "aws-bedrock" ? "aws-sigv4" :
      b.backend_type == "external" ? "none" :
      contains(["aws-bedrock-mantle", "gemini-openai"], b.backend_type) ? "api-key-bearer" :
      b.backend_type == "gemini" ? "api-key-gemini" :
      b.backend_type == "anthropic" ? "api-key-anthropic" :
      "managed-identity"
    )
  }

  # The header APIM adds when it calls the backend (credentials.header of the backend
  # resource). Key-based types reference the named value of auth_config.named_value_key:
  # APIM substitutes {{name}} when the backend is saved, but only when it is the WHOLE
  # header value, so the secret holds the complete value ("Bearer <key>" for
  # api-key-bearer, the bare key for api-key-header). aws-sigv4 is signed in the policy.
  credential_header = {
    for b in var.llm_backend_config : b.backend_id => (
      local.effective_auth_type[b.backend_id] == "managed-identity" ? tomap({ "x-ms-client-id" = [var.managed_identity_client_id] }) :
      local.effective_auth_type[b.backend_id] == "api-key-bearer" ? tomap({ "Authorization" = ["{{${try(b.auth_config.named_value_key, "")}}}"] }) :
      local.effective_auth_type[b.backend_id] == "api-key-header" ? tomap({ "api-key" = ["{{${try(b.auth_config.named_value_key, "")}}}"] }) :
      local.effective_auth_type[b.backend_id] == "api-key-gemini" ? tomap({ "x-goog-api-key" = ["{{${try(b.auth_config.named_value_key, "")}}}"] }) :
      local.effective_auth_type[b.backend_id] == "api-key-anthropic" ? tomap({ "x-api-key" = ["{{${try(b.auth_config.named_value_key, "")}}}"], "anthropic-version" = ["{{anthropic-version}}"] }) :
      null
    )
  }
}

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

      # One rule per backend (the APIM limit), built from the backend's own circuit_breaker.
      circuitBreaker = each.value.circuit_breaker.enabled ? {
        rules = [{
          failureCondition = {
            count            = each.value.circuit_breaker.failure_count
            errorReasons     = each.value.circuit_breaker.error_reasons
            interval         = each.value.circuit_breaker.failure_interval
            statusCodeRanges = [for r in each.value.circuit_breaker.status_code_ranges : { min = r.min, max = r.max }]
          }
          name             = "${each.value.backend_id}-breaker-rule"
          tripDuration     = each.value.circuit_breaker.trip_duration
          acceptRetryAfter = each.value.circuit_breaker.accept_retry_after
        }]
      } : null

      # Native APIM backend credentials: managed identity (token for Cognitive Services) or a
      # static header from a named value, per the effective auth type (see local.credential_header).
      # aws-sigv4 and none need nothing here (SigV4 is computed in the policy).
      credentials = {
        managedIdentity = local.effective_auth_type[each.value.backend_id] == "managed-identity" ? {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        } : null
        header = local.credential_header[each.value.backend_id]
      }

      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }
}

# -----------------------------------------------------------------------------
# LLM BACKEND POOLS (load balancer)
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend_pool" {
  for_each = local.pool_configs

  # 2025-03-01-preview: pool.sessionAffinity (session-aware load balancing) only exists from
  # this version; the backends themselves stay on 2024-06-01-preview.
  type      = "Microsoft.ApiManagement/service/backends@2025-03-01-preview"
  name      = each.key
  parent_id = var.api_management_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Backend pool for model: ${each.value.model_name} (${each.value.backend_type})"
      type        = "Pool"
      pool = {
        services = [for b in each.value.backends : {
          id       = "/backends/${b.backend_id}"
          priority = b.priority
          weight   = b.weight
        }]
        # Sticky routing for stateful models (OpenAI Responses, Assistants): APIM sets an affinity
        # cookie and routes a client that replays it back to the same backend. Stateless model
        # pools keep pure load balancing.
        sessionAffinity = each.value.session_aware ? {
          sessionId = {
            source = each.value.session_affinity.source
            name   = each.value.session_affinity.cookie_name
          }
        } : null
      }
    }
  }

  depends_on = [azapi_resource.llm_backend]
}

# -----------------------------------------------------------------------------
# Dynamic code generation (reduce/map over llmBackendConfig)
# -----------------------------------------------------------------------------

locals {
  # -- set-backend-pools: per-pool C# JObject blocks (pool entries
  #    include authType + authConfigNamedValue so credentials resolve per pool).
  real_pools_code = join("\n", [
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

  # -- Model aliases are virtual pools of the same backendPools array (set-target-backend-pool
  #    resolves them). Each member carries the pools that host its model, resolved here, so the
  #    runtime can fall back across providers on 429/5xx and pick the pool whose type fits the
  #    inbound API surface (a model can be hosted by a native and an OpenAI-compatible pool).
  alias_pools_code = join("\n\n", [
    for i, a in var.model_aliases : join("\n", [
      "// Alias pool: ${a.name} (strategy: ${a.strategy})",
      "var aliasMembers_${i} = new JArray();",
      join("\n", [
        for j, m in a.models :
        "aliasMembers_${i}.Add(new JObject() { { \"model\", \"${m}\" }, { \"weight\", ${length(a.weights) > 0 ? a.weights[j] : 1} }, { \"pools\", new JArray() { ${join(", ", [
          for p in local.all_pools :
          "new JObject() { { \"poolName\", \"${p.pool_name}\" }, { \"poolType\", \"${p.pool_type}\" }, { \"authType\", \"${p.auth_type}\" }, { \"authConfigNamedValue\", \"${p.auth_config_named_value}\" } }"
          if contains(p.supported_models, m)
        ])} } } });"
      ]),
      "var aliasPool_${i} = new JObject()",
      "{",
      "    { \"poolName\", \"alias:${a.name}\" },",
      "    { \"poolType\", \"alias\" },",
      "    { \"isAlias\", true },",
      "    { \"aliasName\", \"${a.name}\" },",
      "    { \"strategy\", \"${a.strategy}\" },",
      "    { \"supportedModels\", new JArray(\"${a.name}\") },",
      "    { \"members\", aliasMembers_${i} }",
      "};",
      "backendPools.Add(aliasPool_${i});"
    ])
  ])

  backend_pools_code = length(var.model_aliases) == 0 ? local.real_pools_code : "${local.real_pools_code}\n\n// ===== Model alias virtual pools (resolve to the underlying real-model pools at runtime) =====\n${local.alias_pools_code}"

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

  # -- metadata-config: per-unique-model mapping (first seen wins for the settings; the last
  #    pool that hosts the model is its default target, as in the upstream generator).
  metadata_models = [
    for model_name in distinct([for m in local.flattened_models : m.name]) : {
      name      = model_name
      pool_name = try(reverse([for p in local.all_pools : p.pool_name if contains(p.supported_models, model_name)])[0], "")
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
      modelPath = try(flatten([
        for b in var.llm_backend_config : [
          for mm in b.supported_models : mm.modelPath if mm.name == model_name && mm.modelPath != ""
        ]
      ])[0], "")
    }
  ]

  metadata_models_code = join(",\n", [
    for m in local.metadata_models :
    "\t\t\t'${m.name}': {\n\t\t\t\t'backend': '${m.pool_name}',\n\t\t\t\t'apiVersion': '${m.apiVersion}',\n\t\t\t\t'timeout': ${m.timeout}${m.inferenceApiVersion != "" ? ",\n\t\t\t\t'inferenceApiVersion': '${m.inferenceApiVersion}'" : ""}${m.modelPath != "" ? ",\n\t\t\t\t'modelPath': '${m.modelPath}'" : ""}\n\t\t\t}"
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

  # -- Alias discovery entries (aliasDeploymentEntries). Each alias
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
  description       = "Post-resolution body rewrite for model aliases (resolution itself happens in set-target-backend-pool)"
  value             = file("${path.module}/templates/frag-resolve-model-alias.xml")
}

# -----------------------------------------------------------------------------
# BACKEND CONTRACT — the live routing contract as JSON, served by the Release Version
# API (GET /version/backend-contract). Same shape as the upstream accelerator's contract,
# so tooling written against it keeps working.
# -----------------------------------------------------------------------------

locals {
  # Version of the contract document itself (bump when its shape changes).
  backend_contract_version = "1.1.0"

  apim_id_parts = split("/", var.api_management_id)

  backend_contract = {
    masterVersion          = var.release_version
    backendContractVersion = local.backend_contract_version
    apim = {
      subscriptionId    = local.apim_id_parts[2]
      resourceGroupName = local.apim_id_parts[4]
      name              = local.apim_id_parts[8]
    }
    sessionAffinity = {
      enabled = var.session_affinity.enabled
      defaults = {
        cookieName = var.session_affinity.cookie_name
        source     = var.session_affinity.source
      }
    }
    modelAliases = [for a in var.model_aliases : { name = a.name, models = a.models, strategy = a.strategy, weights = a.weights }]
    # The credentials stay out: only the NAME of the named value that holds a key is listed.
    backends = [
      for b in var.llm_backend_config : {
        backendId   = b.backend_id
        backendType = b.backend_type
        endpoint    = b.endpoint
        authType    = local.effective_auth_type[b.backend_id]
        authConfig  = { namedValueKey = try(b.auth_config.named_value_key, "") }
        priority    = b.priority
        weight      = b.weight
        circuitBreaker = {
          enabled          = b.circuit_breaker.enabled
          failureCount     = b.circuit_breaker.failure_count
          failureInterval  = b.circuit_breaker.failure_interval
          tripDuration     = b.circuit_breaker.trip_duration
          acceptRetryAfter = b.circuit_breaker.accept_retry_after
          errorReasons     = b.circuit_breaker.error_reasons
          statusCodeRanges = b.circuit_breaker.status_code_ranges
        }
        sessionAffinity = b.session_affinity == null ? {} : { for k, v in { cookieName = b.session_affinity.cookie_name, source = b.session_affinity.source } : k => v if v != null }
        supportedModels = b.supported_models
      }
    ]
    pools = [
      for p in local.all_pools : {
        poolName             = p.pool_name
        poolType             = p.pool_type
        authType             = p.auth_type
        authConfigNamedValue = p.auth_config_named_value
        supportedModels      = p.supported_models
      }
    ]
  }

  # jsonencode already escapes & < > as \u00xx, so the JSON is safe inside the XML body.
  backend_contract_xml = replace(
    file("${path.module}/templates/frag-backend-contract.xml"),
    "//{backendContractJson}",
    jsonencode(local.backend_contract)
  )
}

resource "azurerm_api_management_policy_fragment" "backend_contract" {
  api_management_id = var.api_management_id
  name              = "backend-contract"
  format            = "rawxml"
  description       = "Returns the active LLM backend routing contract (version, pools, backends) deployed on this gateway"
  value             = local.backend_contract_xml
}

