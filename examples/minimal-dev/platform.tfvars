apim = {
  sku              = "StandardV2"
  vnet_mode        = "none"
  private_endpoint = false
  publisher_name   = "Contoso"
  publisher_email  = "ai-gateway@contoso.com"
}

features = { api_center = false, semantic_cache = false }

foundry = {
  network_injection_enabled = false
  instances                 = [{ location = "swedencentral", network_injection_enabled = false }]

  models = [
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 10 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "workflow_standard", sku = "WS1", code_deploy = true }
}
monitoring = { app_insights_dashboards = false }
dev_access = { allowed_cidrs = ["<your-public-ip>/32"] }
