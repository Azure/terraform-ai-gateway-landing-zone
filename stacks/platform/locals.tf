locals {
  stack                  = "platform"
  foundry_instance_names = [for i in var.foundry.instances : i.name]
  greenfield             = var.network_mode == "greenfield"

  apim_cfg = {
    sku                   = var.apim.sku
    capacity              = var.apim.capacity
    publisher_email       = var.apim.publisher_email
    publisher_name        = var.apim.publisher_name
    vnet_mode             = coalesce(var.apim.vnet_mode, contains(["StandardV2", "PremiumV2"], var.apim.sku) ? "integration" : "external")
    public_ip_address_id  = var.apim.public_ip_address_id
    private_endpoint      = var.apim.private_endpoint
    public_network_access = var.apim.public_network_access
  }

  usage_cfg = {
    eventhub = var.usage_pipeline.eventhub
    cosmos   = var.usage_pipeline.cosmos
    logic_app = {
      hosting               = var.usage_pipeline.logic_app.hosting
      hosting_model         = var.usage_pipeline.logic_app.hosting == "ase_v3" ? "AppServiceEnvironmentV3" : "WorkflowStandard"
      ws_sku                = var.usage_pipeline.logic_app.hosting == "workflow_standard" ? coalesce(var.usage_pipeline.logic_app.sku, "WS1") : "WS1"
      ase_sku               = var.usage_pipeline.logic_app.hosting == "ase_v3" ? coalesce(var.usage_pipeline.logic_app.sku, "I1v2") : "I1v2"
      worker_count          = var.usage_pipeline.logic_app.worker_count
      max_worker_count      = var.usage_pipeline.logic_app.max_worker_count
      deployment            = var.usage_pipeline.logic_app.deployment
      content_share_name    = var.usage_pipeline.logic_app.content_share_name
      private_endpoint      = var.usage_pipeline.logic_app.private_endpoint
      public_network_access = var.usage_pipeline.logic_app.public_network_access
      private_endpoint_name = var.usage_pipeline.logic_app.private_endpoint_name != null ? var.usage_pipeline.logic_app.private_endpoint_name : ""
      code_deploy           = var.usage_pipeline.logic_app.code_deploy
      code_source_path      = var.usage_pipeline.logic_app.code_source_path
    }
    ase = var.usage_pipeline.ase
  }

  byo_workspace = var.monitoring.log_analytics_workspace_id != null

  # dev_access CIDRs open the Key Vault and usage-storage firewalls (default Deny).
  dev_cidrs = [for r in var.dev_access.allowed_cidrs : strcontains(r, "/") ? r : "${r}/32"]
}
