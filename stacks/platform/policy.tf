# Keep the usage pipeline keyless (WP-2b.9): deny shared-key storage in the
# workload resource group. The state account lives in its own group.
resource "azurerm_resource_group_policy_assignment" "deny_storage_shared_key" {
  count                = var.deny_storage_shared_key ? 1 : 0
  name                 = "deny-storage-shared-key"
  display_name         = "Storage accounts should prevent shared key access (AI gateway)"
  resource_group_id    = local.resource_group_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54"

  parameters = jsonencode({
    effect = { value = "Deny" }
  })

  lifecycle {
    precondition {
      condition     = local.usage_cfg.logic_app.hosting == "ase_v3"
      error_message = "deny_storage_shared_key needs usage_pipeline.logic_app.hosting = \"ase_v3\": the Workflow Standard runtime requires shared-key storage."
    }
  }

  # Assign after the keyless account exists so the policy never blocks its creation.
  depends_on = [module.logic_app]
}

check "dev_access_scope" {
  assert {
    condition     = length(var.dev_access.allowed_cidrs) == 0 || (local.greenfield && var.environment != "prod")
    error_message = "dev_access opens the Key Vault and storage firewalls to public CIDRs: only for greenfield non-prod environments. Use a private runner (snet-cicd) instead."
  }
}
