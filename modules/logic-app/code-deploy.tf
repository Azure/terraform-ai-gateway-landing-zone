# =============================================================================
# MODULE: Logic App — Workflow Code Publish
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
}

data "archive_file" "workflow_code" {
  count       = local.code_deploy_enabled ? 1 : 0
  type        = "zip"
  source_dir  = var.code_source_path
  output_path = "${path.module}/.artifacts/usage-ingestion-logicapp-${var.random_suffix}.zip"
  excludes    = ["workflow-designtime", ".funcignore", "local.settings.json"]
}

resource "null_resource" "publish_workflows" {
  count = local.code_deploy_enabled ? 1 : 0

  # Re-run whenever the site is re-created or any source file changes.
  triggers = {
    logic_app_id = azurerm_logic_app_standard.usage_ingestion.id
    code_sha256  = data.archive_file.workflow_code[0].output_sha256
    zip_path     = data.archive_file.workflow_code[0].output_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
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
      echo "       site: ${azurerm_logic_app_standard.usage_ingestion.name}"
      echo "       rg  : ${var.resource_group_name}"
      echo "       zip : ${data.archive_file.workflow_code[0].output_path}"
      echo "       sha : ${data.archive_file.workflow_code[0].output_sha256}"

      az functionapp deployment source config-zip \
        --resource-group "${var.resource_group_name}" \
        --name           "${azurerm_logic_app_standard.usage_ingestion.name}" \
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
    azurerm_role_assignment.logic_app_system_eh_owner,
    azurerm_role_assignment.logic_app_system_monitor_reader,
    azurerm_cosmosdb_sql_role_assignment.logic_app_system_mi,
    azapi_resource.azuremonitor_connection,
    azapi_resource.azuremonitor_connection_access,
    azurerm_private_endpoint.storage_blob,
    azurerm_private_endpoint.storage_file,
    azurerm_private_endpoint.storage_table,
    azurerm_private_endpoint.storage_queue,
  ]
}
