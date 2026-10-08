# =============================================================================
# APIM POLICY FRAGMENTS — deploys a map of policy fragments.
# Bicep parity: policy-fragments.bicep + llm-policy-fragments.bicep (static part).
# =============================================================================

resource "azurerm_api_management_policy_fragment" "this" {
  for_each = var.fragments

  api_management_id = var.api_management_id
  name              = each.key
  format            = "rawxml"
  description       = each.value.description
  value             = each.value.xml

  # APIM's CreateOrUpdate LRO intermittently returns 404 ResourceNotFound on
  # the status endpoint before the fragment is queryable (eventual consistency
  # on the control plane). Give the provider enough time to keep polling
  # instead of failing on the first 404.
  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
  }

  depends_on = [var.depends_on_ids]
}

# Fragments managed via azapi: the azurerm resource has a known LRO polling bug
# ("polling after CreateOrUpdate: 404 Not Found: PolicyFragment not found").
# azapi does a direct idempotent PUT and doesn't rely on that poller.
resource "azapi_resource" "this" {
  for_each = var.azapi_fragments

  type      = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  name      = each.key
  parent_id = var.api_management_id

  body = {
    properties = {
      value       = each.value.xml
      format      = "rawxml"
      description = each.value.description
    }
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
  }

  depends_on = [var.depends_on_ids]
}
