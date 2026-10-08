# =============================================================================
# NAMING — one place that produces every resource name.
#
# Every name is deterministic (derived from resource group, environment and
# subscription), so names are known at plan time and a single apply can create
# everything. Explicit names arrive through name_overrides and always win.
# =============================================================================

locals {
  # Bicep-parity seed: sha256("<rg>-<env>-<subscription>")[0:10]
  resource_token = substr(sha256("${var.resource_group_name}-${var.environment_name}-${var.subscription_id}"), 0, 10)
  env            = var.environment_name
  # 6-character suffix for globally unique names (storage accounts allow
  # lowercase letters and digits only).
  sfx = substr(sha256("suffix-${local.resource_token}"), 0, 6)

  generated = {
    resource_group          = "rg-${local.env}"
    apim                    = "apim-${local.resource_token}"
    cosmos                  = "cosmos-${local.resource_token}"
    eventhub_namespace      = "evhns-${local.resource_token}"
    log_analytics           = "law-${local.resource_token}"
    key_vault               = "kv-${local.resource_token}"
    virtual_network         = "vnet-${local.env}"
    uami_apim               = "id-apim-${local.env}-${local.sfx}"
    uami_usage              = "id-logicapp-${local.env}-${local.sfx}"
    redis                   = "redis-${local.env}-${local.sfx}"
    api_center              = "apic-${local.env}-${local.sfx}"
    storage_logic           = "stla${local.sfx}"
    logic_app               = "logic-usage-${local.env}-${local.sfx}"
    logic_content_share     = "logic-content-${local.sfx}"
    app_service_plan        = "asp-logic-${local.env}"
    app_service_environment = "ase-${local.env}-${local.sfx}"
    logic_app_code_artifact = "usage-ingestion-logicapp-${local.sfx}"
  }

  names = merge(local.generated, { for k, v in var.name_overrides : k => v if v != null && v != "" })

  foundry_account_names = [
    for i, n in var.foundry_instance_names : n != "" ? n : "aif-${local.env}-${i}-${local.sfx}"
  ]
}
