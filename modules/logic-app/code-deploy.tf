# =============================================================================
# MODULE: Logic App — Workflow Code Publish
#
#   run_from_package (ase_v3 default, WP-2b.4): the zip is uploaded to the
#     keyless storage account's "deployments" container (data plane, Entra ID;
#     the storage account has no public endpoint, so apply runs from a runner
#     with access to the storage private endpoint). The site reads it with the
#     usage UAMI (WEBSITE_RUN_FROM_PACKAGE + _BLOB_MI_RESOURCE_ID); a new
#     package changes the URL, then triggers are re-synced. No SCM access.
#   zip_deploy (Workflow Standard, or ase_v3 opt-in): `az` pushes the zip to
#     the site's SCM endpoint (below).
# Mirrors: `azd deploy usageProcessingLogicApp` in ai-hub-gateway-*/azure.yaml
#
# Packages src/usage-ingestion-logicapp/ (host.json, connections.json,
# 4 workflow.json files) and pushes it to the Logic App Standard site via
# `az logicapp deployment source config-zip`. Control-plane deploy — works
# behind the private-endpoint / ILB topology (Kudu is unreachable on V2).
#
# See LOGIC_APP_CODE_PORT.md for the full design rationale.
# =============================================================================

locals {
  code_deploy_enabled = var.enable_code_deploy && var.code_source_path != ""
  zip_deploy_enabled  = local.code_deploy_enabled && !local.run_from_package
  package_enabled     = local.code_deploy_enabled && local.run_from_package

  # Content-addressed blob: a new package => a new URL => the site reloads it.
  package_blob_name = local.package_enabled ? "usage-ingestion-${substr(data.archive_file.workflow_code[0].output_sha256, 0, 16)}.zip" : ""
  package_url       = local.package_enabled ? "${local.storage_endpoints.blob}/deployments/${local.package_blob_name}" : ""
}

# The identity running apply writes the package (data plane, Entra ID).
resource "azurerm_role_assignment" "deployer_package_writer" {
  count                = local.package_enabled ? 1 : 0
  scope                = "${module.storage.resource_id}/blobServices/default/containers/deployments"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [module.storage]
}

resource "azurerm_storage_blob" "package" {
  count                  = local.package_enabled ? 1 : 0
  name                   = local.package_blob_name
  storage_account_name   = module.storage.name
  storage_container_name = "deployments"
  type                   = "Block"
  source                 = data.archive_file.workflow_code[0].output_path
  content_md5            = data.archive_file.workflow_code[0].output_md5

  depends_on = [azurerm_role_assignment.deployer_package_writer]
}

# Re-sync the workflow triggers once the site runs the new package.
resource "terraform_data" "package_version" {
  count = local.package_enabled ? 1 : 0
  input = local.package_blob_name
}

resource "azapi_resource_action" "restart" {
  count       = local.package_enabled ? 1 : 0
  type        = "Microsoft.Web/sites@2024-04-01"
  resource_id = azapi_resource.usage_ingestion_ase[0].id
  action      = "restart"
  method      = "POST"

  depends_on = [azurerm_storage_blob.package, azapi_resource.usage_ingestion_ase]

  lifecycle {
    replace_triggered_by = [terraform_data.package_version]
  }
}

resource "azapi_resource_action" "sync_triggers" {
  count       = local.package_enabled ? 1 : 0
  type        = "Microsoft.Web/sites@2024-04-01"
  resource_id = azapi_resource.usage_ingestion_ase[0].id
  action      = "syncfunctiontriggers"
  method      = "POST"

  depends_on = [azapi_resource_action.restart]

  lifecycle {
    replace_triggered_by = [terraform_data.package_version]
  }
}

data "archive_file" "workflow_code" {
  count       = local.code_deploy_enabled ? 1 : 0
  type        = "zip"
  source_dir  = var.code_source_path
  output_path = "${path.module}/.artifacts/${var.names.code_artifact}.zip"
  excludes    = ["workflow-designtime", ".funcignore", "local.settings.json"]
}

resource "null_resource" "publish_workflows" {
  count = local.zip_deploy_enabled ? 1 : 0

  # Re-run whenever the site is re-created or any source file changes.
  triggers = {
    logic_app_id = local.logic_app_id
    code_sha256  = data.archive_file.workflow_code[0].output_sha256
    zip_path     = data.archive_file.workflow_code[0].output_path
  }

  # On an internal (ILB) ASE v3 the zip is pushed to the app's SCM endpoint
  # (<app>.scm.<ase>.appserviceenvironment.net), which only resolves and is only
  # reachable from inside the VNet — run apply from a VNet-connected agent.
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      if ! command -v az >/dev/null 2>&1; then
        echo "ERROR: az CLI not found on PATH. Install from https://aka.ms/installazurecli" >&2
        exit 1
      fi

      # Logic App Standard runs on the Functions host, so the Functions
      # zip-deploy command is the supported control-plane path. No extension
      # install needed (ships in core az CLI).
      echo "[INFO] Publishing Logic App workflow code"
      echo "       site: ${local.logic_app_name}"
      echo "       rg  : ${var.resource_group_name}"
      echo "       zip : ${data.archive_file.workflow_code[0].output_path}"
      echo "       sha : ${data.archive_file.workflow_code[0].output_sha256}"

      az functionapp deployment source config-zip \
        --resource-group "${var.resource_group_name}" \
        --name           "${local.logic_app_name}" \
        --src            "${data.archive_file.workflow_code[0].output_path}" \
        ${var.subscription_id != "" ? format("--subscription %q", var.subscription_id) : ""} \
        --only-show-errors

      echo "[OK] Workflow code published."
    EOT
  }

  # All of these must be in place before the first workflow run, otherwise
  # triggers fail at runtime (missing MI roles, missing API connection,
  # missing app settings, etc.).
  depends_on = [
    azurerm_logic_app_standard.usage_ingestion,
    azapi_resource.usage_ingestion_ase,
    azurerm_role_assignment.logic_app_system_eh_owner,
    azurerm_role_assignment.logic_app_system_monitor_reader,
    azurerm_cosmosdb_sql_role_assignment.logic_app_system_mi,
    azapi_resource.azuremonitor_connection,
    azapi_resource.azuremonitor_connection_access,
    module.storage,
  ]
}
