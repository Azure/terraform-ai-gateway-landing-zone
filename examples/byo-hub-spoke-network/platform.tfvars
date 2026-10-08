apim = {
  sku             = "Developer"
  vnet_mode       = "internal"
  publisher_name  = "Contoso"
  publisher_email = "ai-gateway@contoso.com"
}

network = {
  vnet_id = "/subscriptions/<sub>/resourceGroups/<rg-net>/providers/Microsoft.Network/virtualNetworks/<vnet>"
  subnet_ids = {
    pe        = "/subscriptions/<sub>/resourceGroups/<rg-net>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<pe>"
    apim      = "/subscriptions/<sub>/resourceGroups/<rg-net>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<apim>"
    logic_app = "/subscriptions/<sub>/resourceGroups/<rg-net>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<logic>"
  }
  # Logical key (modules/naming private_dns_zones) => zone ID.
  private_dns_zone_ids = {
    key_vault          = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    cosmos_db          = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
    event_hub          = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net"
    cognitive_services = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
    openai             = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
    ai_services        = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
    storage_blob       = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    storage_file       = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    storage_table      = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    storage_queue      = "/subscriptions/<sub>/resourceGroups/<rg-dns>/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
  }
}

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

secret_writer_principal_ids = { pipeline = "<apply-principal-id>" }
secret_reader_principal_ids = { pipeline = "<plan-principal-id>" }
