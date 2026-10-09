# =============================================================================
# MODULE: Foundry - Outputs
# Mirrors bicep module outputs:
#   - extendedAIServicesConfig
#   - aiFoundryPrincipalIds
# =============================================================================

output "diagnostic_setting_names" {
  description = "Workload diagnostic setting names (empty when policy owns diagnostics)."
  value       = [for setting in azurerm_monitor_diagnostic_setting.foundry : setting.name]
}

output "foundry_ids" {
  description = "Resource IDs for each AI Foundry (AIServices) account."
  value       = local.account_ids
}

output "foundry_names" {
  description = "Names of each AI Foundry account."
  value       = local.account_names
}

output "foundry_endpoints" {
  description = "Endpoint for each AI Foundry account."
  value = [
    for e in local.account_endpoints : coalesce(e, "")
  ]
}

output "foundry_principal_ids" {
  description = "System-assigned managed identity principal IDs for each Foundry account."
  value = [
    for p in local.account_principal_ids : coalesce(p, "")
  ]
}

output "project_ids" {
  description = "Resource IDs of the default Foundry projects (one per account)."
  value       = azapi_resource.project[*].id
}

output "project_names" {
  description = "Names of the default Foundry projects (one per account)."
  value       = azapi_resource.project[*].name
}

# Parity with Bicep output extendedAIServicesConfig
output "extended_ai_services_config" {
  description = "Per-instance Foundry details including the Foundry project endpoint."
  value = [
    for i, name in local.account_names : {
      name                     = name
      location                 = var.foundry_instances[i].location
      cognitive_service_id     = local.account_ids[i]
      cognitive_service_name   = name
      endpoint                 = coalesce(local.account_endpoints[i], "")
      foundry_project_endpoint = "https://${name}.services.ai.azure.com/api/projects/${azapi_resource.project[i].name}"
    }
  ]
}

output "primary_foundry_endpoint" {
  description = "Base AI Services endpoint of the primary (index 0) Foundry account; serves content-safety + PII."
  # Endpoint host is the account's customSubDomainName (instance_subdomains[0]),
  # NOT the raw name (which may be empty when auto-generated or overridden by
  # custom_subdomain). instance_subdomains already lowercases + falls back.
  value = length(local.instances) > 0 ? "https://${local.instance_subdomains[0]}.cognitiveservices.azure.com/" : ""
}