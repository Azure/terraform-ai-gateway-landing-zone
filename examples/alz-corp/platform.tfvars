apim = {
  sku             = "Premium"
  capacity        = 3 # zone redundant (zones 1-3)
  vnet_mode       = "internal"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

# task output STACK=network NAME=platform_network
network = {
  vnet_id = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>"
  subnet_ids = {
    pe    = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>/subnets/snet-pe"
    apim  = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>/subnets/snet-apim"
    agent = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>/subnets/snet-agent"
  }
  # DINE binds the covered zones; Terraform binds the ones the policy doesn't cover.
  dns_zone_groups_managed_by_policy = true
  private_dns_zone_ids = {
    openai       = "/subscriptions/<hub-sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
    ai_services  = "/subscriptions/<hub-sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
    apim_gateway = "/subscriptions/<hub-sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
  }
}

foundry = {
  instances = [{ location = "swedencentral" }, { location = "eastus2" }]
  models = [
    { name = "gpt-5.4", version = "2026-03-05", capacity = 100, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 100, ai_service_index = 0 },
    { name = "gpt-5.4-mini", version = "2026-03-17", capacity = 100, ai_service_index = 1 },
  ]
}

usage_pipeline = {
  logic_app = { hosting = "ase_v3", sku = "I1v2", worker_count = 2, max_worker_count = 4, code_deploy = true }
  ase       = { zone_redundant = true }
  eventhub  = { public_network_access = "Disabled" }
}

# Diagnostics: the platform DINE sends most to the central workspace (D10). Those services'
# settings belong to Policy, so no workload settings are created for them.
# Private monitoring: the App Insights components join the hub's Azure Monitor Private Link Scope
# (one scope per DNS: a second one here would overwrite the hub's records in the shared zones) and
# accept telemetry only through it. Public query stays on the APIM component, which the usage
# pipeline's Logic App connector queries through Resource Manager, and is closed on the Logic App
# and Foundry components. The central workspace keeps the platform team's settings, but it must
# accept public queries: the APIM component's data lives there, and a closed workspace returns the
# connector's queries empty.
monitoring = {
  log_analytics_workspace_id     = "/subscriptions/<mgmt-sub>/resourceGroups/<rg-mgmt>/providers/Microsoft.OperationalInsights/workspaces/<law>"
  policy_managed_diagnostics     = ["cosmosdb", "eventhub", "foundry"]
  existing_private_link_scope_id = "/subscriptions/<hub-sub>/resourceGroups/<rg-hub-monitor>/providers/Microsoft.Insights/privateLinkScopes/<ampls-hub>"
  public_ingestion_enabled       = false
  public_query_enabled           = false
  # Managed identity ingestion only (the default): the APIM and Logic App components have local
  # authentication off, as the built-in policy "Application Insights components should block
  # non-Azure Active Directory based ingestion" (MCSB IM-1) requires.
  app_insights_entra_ingestion = true
}

# Logger credentials as Key Vault secrets read through Key Vault-backed named values (the default):
# APIM keeps no secret named values of its own, as "API Management secret named values should be
# stored in Azure Key Vault" requires. APIM (internal VNet) reaches the vault's private endpoint.
apim_logging = { credentials_in_key_vault = true }

deny_storage_shared_key = false # ALZ assigns Deny-Storage-Shared-Key at the MG

secret_writer_principal_ids = { pipeline = "<vended-apply-principal-id>" }
secret_reader_principal_ids = { pipeline = "<vended-plan-principal-id>" }
