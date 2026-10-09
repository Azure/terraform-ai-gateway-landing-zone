# LLM backends: derived from the Foundry deployments (one backend per account),
# extended or replaced by tfvars (review 7.5.6).

locals {
  foundry_derived = [
    for i, name in local.foundry_account_names : {
      backend_id   = "foundry-${data.azurerm_cognitive_account.foundry[name].location}-${i}"
      backend_type = "ai-foundry"
      endpoint     = data.azurerm_cognitive_account.foundry[name].endpoint
      auth_scheme  = "managedIdentity"
      auth_type    = "managed-identity"
      auth_config  = null
      priority     = i == 0 ? 1 : 2
      weight       = 100
      supported_models = [
        for d in try(data.azapi_resource_list.deployments[name].output.deployments, []) : {
          name                = d.name
          sku                 = d.sku
          capacity            = d.capacity
          modelFormat         = d.format
          modelVersion        = d.version
          apiVersion          = var.foundry_backends.api_version
          timeout             = 120
          inferenceApiVersion = ""
          retirementDate      = ""
        }
      ]
    }
  ]

  # Two for-expressions instead of a conditional: the branch types differ (a typed
  # variable vs. a tuple of heterogeneous objects) and a conditional needs one type.
  llm_backend_config = concat(
    [for b in var.llm_backend_config : b],
    [for b in concat(local.foundry_derived, var.extra_llm_backends) : b if length(var.llm_backend_config) == 0],
  )
}

# Backends, pools, circuit breakers and the generated routing fragments
# (set-backend-pools, get-available-models, metadata-config, resolve-model-alias).
module "llm_routing" {
  source = "../../modules/llm-routing"

  api_management_id          = local.apim_id
  managed_identity_client_id = data.azurerm_user_assigned_identity.apim.client_id
  llm_backend_config         = local.llm_backend_config
  model_aliases              = var.model_aliases
  configure_circuit_breaker  = var.configure_circuit_breaker
}

# Without Foundry (platform foundry.enabled = false) the backends come from
# extra_llm_backends / llm_backend_config; with none the LLM APIs route nowhere.
check "llm_backends_exist" {
  assert {
    condition     = length(local.llm_backend_config) > 0
    error_message = "No LLM backends: no Foundry account was found and neither extra_llm_backends nor llm_backend_config is set, so the LLM APIs have nothing to route to. Deploy Foundry in stacks/platform, or list your backends in extra_llm_backends."
  }
}
