# =============================================================================
# LLM BACKENDS: which APIM backends this stack deploys
#
# Every backend is one entry in local.all_llm_backends, the concatenation of
# two sources, in this order:
#
#   1. Foundry-derived  (foundry_backends)
#        One backend per Foundry account of stacks/platform (found by the naming
#        contract aif-<workload>-<environment>-<n>, or by foundry_backends.account_names),
#        serving every model deployed on that account. Read from Azure, so the model list
#        is never repeated here. Auth is the APIM managed identity.
#        The first account has priority 1, the others priority 2, all weight 100.
#
#   2. Your own  (llm_backends)
#        Anything else: Azure OpenAI outside Foundry, a third-party OpenAI-compatible
#        endpoint, AWS Bedrock, or a Foundry account stacks/platform doesn't own.
#
#   foundry_backends.enabled   llm_backends   backends deployed
#   -------------------------  -------------  -----------------------------------------
#   true (default)             []             one per Foundry account
#   true                       [a, b]         one per Foundry account, then a and b
#   false                      [a, b]         a and b only
#   false                      []             none (flagged by the check below)
#
# Both sources take the same per-backend circuit_breaker settings:
# foundry_backends.circuit_breaker for every derived backend, llm_backends[*].circuit_breaker
# for each of your own.
#
# What modules/llm-routing then creates from that list:
#   - one APIM backend per entry (its endpoint, credentials and circuit breaker);
#   - one backend POOL per (model, backend type) that two or more backends serve, named
#     <model>-<type>-backend-pool (traffic follows each backend's priority and weight; a
#     model flagged sessionAwareModel gets session affinity); a model served by a single
#     backend of its type is routed to that backend directly;
#   - the routing fragments of the policies (set-backend-pools, which also carries one
#     virtual pool per model alias, get-available-models, metadata-config,
#     resolve-model-alias) and the backend-contract fragment served at /version/backend-contract.
# The result is listed in the llm_backends output.
# =============================================================================

locals {
  # Source 1: one entry per Foundry account (empty when foundry_backends.enabled = false).
  foundry_derived = [
    for i, name in local.foundry_account_names : {
      backend_id       = "foundry-${data.azurerm_cognitive_account.foundry[name].location}-${i}"
      backend_type     = "ai-foundry"
      endpoint         = data.azurerm_cognitive_account.foundry[name].endpoint
      auth_scheme      = "managedIdentity"
      auth_type        = "managed-identity"
      auth_config      = null
      priority         = i == 0 ? 1 : 2
      weight           = 100
      circuit_breaker  = var.foundry_backends.circuit_breaker
      session_affinity = null
      # The deployments of the account, as Azure reports them.
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
          modelPath           = ""
          sessionAwareModel   = contains(var.foundry_backends.session_aware_models, d.name)
        }
      ]
    }
  ]

  # Everything that becomes an APIM backend: source 1, then source 2 (var.llm_backends).
  all_llm_backends = concat(local.foundry_derived, var.llm_backends)
}

# Backends, pools, circuit breakers and the generated routing fragments.
module "llm_routing" {
  source = "../../modules/llm-routing"

  api_management_id          = local.apim_id
  managed_identity_client_id = data.azurerm_user_assigned_identity.apim.client_id
  llm_backend_config         = local.all_llm_backends
  model_aliases              = var.model_aliases
  session_affinity           = var.session_affinity
  release_version            = local.release_version

  # APIM resolves the {{named values}} of the backend credentials when it saves a backend,
  # and refuses a backend whose named value doesn't exist yet.
  depends_on = [
    azurerm_api_management_named_value.backend_api_key,
    azurerm_api_management_named_value.anthropic_version,
  ]
}

# Without Foundry (platform foundry.enabled = false, or foundry_backends.enabled = false)
# the backends come from llm_backends; with none the LLM APIs route nowhere.
check "llm_backends_exist" {
  assert {
    condition     = length(local.all_llm_backends) > 0
    error_message = "No LLM backends: no Foundry account was found and llm_backends is empty, so the LLM APIs have nothing to route to. Deploy Foundry in stacks/platform, or list your backends in llm_backends."
  }
}
