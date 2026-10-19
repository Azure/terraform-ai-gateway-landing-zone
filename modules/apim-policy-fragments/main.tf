# =============================================================================
# APIM POLICY FRAGMENTS — deploys a map of policy fragments.
# =============================================================================

locals {
  # Usage event markers (see var.usage_event). Terraform's regex replace substitutes $1 / $2 with the
  # marker's status and reason; the body has no other "$".
  usage_event_body   = templatefile("${path.module}/templates/usage-event.xml.tftpl", { record_key_rejections = tostring(var.usage_event.record_key_rejections) })
  usage_event_marker = "/<!-- usage-event status=\"([0-9]+)\" reason=\"([a-z0-9-]+)\" -->/"
  usage_event_inline = "<set-variable name=\"usageEventStatus\" value=\"$1\" />\n<set-variable name=\"usageEventReason\" value=\"$2\" />\n${replace(local.usage_event_body, "/(?s)<!--.*?-->\\s*/", "")}"

  fragments       = { for k, f in var.fragments : k => merge(f, { xml = replace(f.xml, local.usage_event_marker, local.usage_event_inline) }) }
  azapi_fragments = { for k, f in var.azapi_fragments : k => merge(f, { xml = replace(f.xml, local.usage_event_marker, local.usage_event_inline) }) }
}

resource "azurerm_api_management_policy_fragment" "this" {
  for_each = local.fragments

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
  for_each = local.azapi_fragments

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
  for_each = local.azapi_fragments
  input    = sha256(jsonencode([each.value.xml, each.value.description]))
}

# Idempotent PUT whenever the fragment XML or description changes.
resource "azapi_resource_action" "update" {
  for_each    = local.azapi_fragments
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
