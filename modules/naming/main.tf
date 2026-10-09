# =============================================================================
# NAMING — the naming contract shared by every stack (review 7.7).
#
# Names are deterministic: <prefix>-<workload>-<environment>[-<seed>]. The seed
# is 5 hex characters of sha256("<subscription>/<workload>/<environment>")
# unless unique_seed is set, so every stack computes the same names without
# reading another stack's state. name_overrides always win.
# =============================================================================

locals {
  seed = coalesce(var.unique_seed, substr(sha256("${var.subscription_id}/${var.workload}/${var.environment}"), 0, 5))
  base = "${var.workload}-${var.environment}"
  # Alphanumeric-only stem for storage accounts (3-24 lowercase letters/digits).
  compact = "${var.workload}${var.environment}"

  generated = {
    # Resource groups: one for Terraform state, one for everything else.
    resource_group       = "rg-${local.base}"
    state_resource_group = "rg-${local.base}-tfstate"

    # Bootstrap
    state_storage_account = "st${substr(local.compact, 0, 15)}${local.seed}tf"
    pipeline_plan         = "id-tf-${local.base}-plan"
    pipeline_apply        = "id-tf-${local.base}-apply"

    # Identity
    # Display names are tenant-wide: the seed keeps same-named environments apart.
    gateway_app = "app-${local.base}-${local.seed}-gateway"

    # Network (subnet names are fixed so downstream stacks can look them up)
    virtual_network  = "vnet-${local.base}"
    subnet_apim      = "snet-apim"
    subnet_pe        = "snet-pe"
    subnet_logic_app = "snet-logic"
    subnet_agent     = "snet-agent"
    subnet_ase       = "snet-ase"
    subnet_cicd      = "snet-cicd"

    # App hosting
    app_service_environment = "ase-${local.base}-${local.seed}"

    # Platform
    apim               = "apim-${local.base}-${local.seed}"
    key_vault          = "kv-${substr(local.base, 0, 14)}-${local.seed}"
    cosmos             = "cosno-${local.base}-${local.seed}"
    eventhub_namespace = "evhns-${local.base}-${local.seed}"
    log_analytics      = "log-${local.base}"
    uami_apim          = "id-${local.base}-apim"
    uami_usage         = "id-${local.base}-usage"
    redis              = "redis-${local.base}-${local.seed}"
    api_center         = "apic-${local.base}-${local.seed}"
    # Standalone Language (TextAnalytics) and Content Safety accounts: custom subdomains, so globally unique.
    language_service        = "lang-${local.base}-${local.seed}"
    content_safety          = "cs-${local.base}-${local.seed}"
    storage_logic           = "st${substr(local.compact, 0, 17)}${local.seed}"
    logic_app               = "logic-${local.base}-${local.seed}"
    logic_content_share     = "logic-content-${local.seed}"
    app_service_plan        = "asp-${local.base}"
    logic_app_code_artifact = "usage-ingestion-logicapp-${local.seed}"
  }

  names = merge(local.generated, { for k, v in var.name_overrides : k => v if v != null && v != "" })

  # Private DNS zones the gateway uses (greenfield: created by stacks/network,
  # looked up by name in platform). Logical key => zone name.
  private_dns_zones = {
    key_vault          = "privatelink.vaultcore.azure.net"
    cosmos_db          = "privatelink.documents.azure.com"
    event_hub          = "privatelink.servicebus.windows.net"
    cognitive_services = "privatelink.cognitiveservices.azure.com"
    openai             = "privatelink.openai.azure.com"
    storage_blob       = "privatelink.blob.core.windows.net"
    storage_file       = "privatelink.file.core.windows.net"
    storage_table      = "privatelink.table.core.windows.net"
    storage_queue      = "privatelink.queue.core.windows.net"
    monitor            = "privatelink.monitor.azure.com"
    apim_gateway       = "privatelink.azure-api.net"
    ai_services        = "privatelink.services.ai.azure.com"
    redis              = "privatelink.redis.azure.net"
  }

  # Zones only some configurations need; stacks/network creates them on request,
  # platform looks them up only when it uses them.
  private_dns_optional_zones = {
    logic_app = "privatelink.azurewebsites.net" # Workflow Standard Logic App private endpoint
  }

  foundry_account_names = [
    for i, n in var.foundry_instance_names : n != "" ? n : "aif-${local.base}-${local.seed}-${i}"
  ]
}
