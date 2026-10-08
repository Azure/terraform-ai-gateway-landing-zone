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

  # APIM reformats the stored XML, so the read-back body never matches; content
  # changes go through azapi_resource_action.update (a fragment in use can't be
  # deleted and recreated).
  lifecycle {
    ignore_changes = [body]
  }

  depends_on = [var.depends_on_ids]
}

resource "terraform_data" "hash" {
  for_each = var.azapi_fragments
  input    = sha256(jsonencode([each.value.xml, each.value.description]))
}

# Idempotent PUT whenever the fragment XML or description changes.
resource "azapi_resource_action" "update" {
  for_each    = var.azapi_fragments
  type        = "Microsoft.ApiManagement/service/policyFragments@2024-05-01"
  resource_id = azapi_resource.this[each.key].id
  method      = "PUT"

  body = {
    properties = {
      value       = each.value.xml
      format      = "rawxml"
      description = each.value.description
    }
  }

  timeouts {
    create = "45m"
  }

  lifecycle {
    replace_triggered_by = [terraform_data.hash[each.key]]
  }
}
