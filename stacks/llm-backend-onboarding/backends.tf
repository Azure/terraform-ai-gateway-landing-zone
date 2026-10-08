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

  llm_backend_config = length(var.llm_backend_config) > 0 ? var.llm_backend_config : concat(local.foundry_derived, var.extra_llm_backends)
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
