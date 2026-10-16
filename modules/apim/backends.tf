# =============================================================================
# APIM BACKENDS — Bicep parity for:
#   llm-backends.bicep, llm-backend-pools.bicep, inference-backend.bicep
#   (contentSafetyBackend, aiSearchBackends, embeddingsBackend in apim.bicep)
#
# azurerm_api_management_backend is used for simple backends. For "Pool"
# type backends (load balancer), azurerm lacks support so we use azapi_resource
# at API version `2024-06-01-preview`.
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
        model       = m
        backend_id  = b.backend_id
        backend_type = b.backend_type
        priority    = b.priority
        weight      = b.weight
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
# LLM BACKENDS (one per endpoint) — llm-backends.bicep
# -----------------------------------------------------------------------------

locals {
  # Per-backend credentials applied natively by APIM on forward-request.
  # auth_type takes precedence over legacy auth_scheme; the type-based fallback
  # mirrors frag-set-target-backend-pool.xml. API-key secrets are referenced as
  # {{named-value}} tokens, which APIM resolves for backend credentials (policy
  # expressions cannot resolve a named value from a runtime variable).
  llm_backend_credentials = {
    for b in var.llm_backend_config : b.backend_id => {
      auth_type = (
        try(b.auth_type, null) != null && try(b.auth_type, "") != "" ? b.auth_type :
        try(b.auth_scheme, "") == "managedIdentity" ? "managed-identity" :
        contains(["aws-bedrock-mantle", "gemini-openai"], b.backend_type) ? "api-key-bearer" : ""
      )
      named_value_key = try(b.auth_config.named_value_key, null) != null ? b.auth_config.named_value_key : ""
      # "" = the named value already holds the full Authorization header value.
      authorization_scheme = try(b.auth_config.authorization_scheme, null) != null ? trimspace(b.auth_config.authorization_scheme) : "Bearer"
    }
  }

  llm_backend_auth = {
    for id, c in local.llm_backend_credentials : id => {
      managed_identity     = contains(["managed-identity", "native-backend-authorization"], c.auth_type)
      api_key_bearer       = c.auth_type == "api-key-bearer" && c.named_value_key != ""
      api_key_header       = c.auth_type == "api-key-header" && c.named_value_key != ""
      authorization_scheme = c.authorization_scheme
      named_value_ref      = "{{${c.named_value_key}}}"
    }
  }

  # Named values referenced by backend credentials (deduplicated).
  llm_backend_api_key_named_values = toset([
    for c in local.llm_backend_credentials : c.named_value_key
    if c.named_value_key != "" && contains(["api-key-bearer", "api-key-header"], c.auth_type)
  ])
}

# Placeholder named values so backend credentials referencing {{key}} can be
# created. Real secrets (Key Vault references) are owned by llm-backend-onboarding.
resource "azurerm_api_management_named_value" "llm_backend_api_key" {
  for_each = local.llm_backend_api_key_named_values

  name                = each.value
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  display_name        = each.value
  value               = "NOT_CONFIGURED"
  secret              = false

  lifecycle {
    ignore_changes = [value, secret, value_from_key_vault]
  }
}

resource "azapi_resource" "llm_backend" {
  for_each = { for b in var.llm_backend_config : b.backend_id => b }

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.value.backend_id
  parent_id = azurerm_api_management.citadel.id

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

      # Native APIM backend credentials:
      # - managed-identity: credentials.managedIdentity (Bicep parity) plus the
      #   x-ms-client-id header for backends that key on it.
      # - api-key-bearer:   Authorization: <authorization_scheme> {{named_value_key}}
      #                     (raw {{named_value_key}} header when the scheme is "")
      # - api-key-header:   api-key: {{named_value_key}}
      # aws-sigv4 is signed per-request in the set-backend-authorization fragment.
      credentials = {
        managedIdentity = local.llm_backend_auth[each.key].managed_identity ? {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        } : null
        authorization = local.llm_backend_auth[each.key].api_key_bearer && local.llm_backend_auth[each.key].authorization_scheme != "" ? {
          scheme    = local.llm_backend_auth[each.key].authorization_scheme
          parameter = local.llm_backend_auth[each.key].named_value_ref
        } : null
        header = (
          local.llm_backend_auth[each.key].managed_identity ? tomap({ "x-ms-client-id" = [var.managed_identity_client_id] }) :
          local.llm_backend_auth[each.key].api_key_header ? tomap({ "api-key" = [local.llm_backend_auth[each.key].named_value_ref] }) :
          # credentials.authorization requires a scheme; send the named value verbatim instead.
          local.llm_backend_auth[each.key].api_key_bearer && local.llm_backend_auth[each.key].authorization_scheme == "" ? tomap({ "Authorization" = [local.llm_backend_auth[each.key].named_value_ref] }) :
          null
        )
      }

      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }

  depends_on = [azurerm_api_management_named_value.llm_backend_api_key]
}

# -----------------------------------------------------------------------------
# LLM BACKEND POOLS (load balancer) — llm-backend-pools.bicep
# -----------------------------------------------------------------------------

resource "azapi_resource" "llm_backend_pool" {
  for_each = local.pool_configs

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = each.key
  parent_id = azurerm_api_management.citadel.id

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
# CONTENT SAFETY BACKEND — apim.bicep contentSafetyBackend
# -----------------------------------------------------------------------------

resource "azapi_resource" "content_safety_backend" {
  count     = var.enable_content_safety ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "content-safety-backend"
  parent_id = azurerm_api_management.citadel.id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Content Safety Service Backend"
      url         = var.content_safety_endpoint
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
      credentials = {
        managedIdentity = {
          clientId = var.managed_identity_client_id
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# AI SEARCH BACKENDS — apim.bicep aiSearchBackends
# -----------------------------------------------------------------------------

resource "azurerm_api_management_backend" "ai_search" {
  for_each = var.enable_azure_ai_search ? { for s in var.ai_search_instances : s.name => s } : {}

  name                = each.value.name
  api_management_name = azurerm_api_management.citadel.name
  resource_group_name = var.resource_group_name
  protocol            = "http"
  url                 = each.value.url
  description         = each.value.description

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

# -----------------------------------------------------------------------------
# EMBEDDINGS BACKEND (for semantic cache) — apim.bicep embeddingsBackend
# The URL is the full embeddings endpoint without a query string (the lookup
# adds api-version). No credentials: llm-semantic-cache-lookup authenticates as
# APIM's system-assigned identity (embeddings-backend-auth="system-assigned",
# the only option), which needs Cognitive Services OpenAI User on the account.
# -----------------------------------------------------------------------------

resource "azapi_resource" "embeddings_backend" {
  count     = var.enable_embeddings_backend ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = var.embeddings_backend_id
  parent_id = azurerm_api_management.citadel.id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Foundry embeddings backend for semantic cache"
      url         = var.embeddings_backend_url
      protocol    = "http"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.embeddings_backend_url != ""
      error_message = "enable_embeddings_backend needs an embeddings endpoint: set primary_foundry_embedding_model_name (an embeddings deployment on the primary Foundry account) or embeddings_backend_url."
    }
    precondition {
      condition     = !strcontains(var.embeddings_backend_url, "?")
      error_message = "embeddings_backend_url must not contain a query string (the semantic cache lookup adds api-version)."
    }
  }
}
