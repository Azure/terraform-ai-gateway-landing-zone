# =============================================================================
# MODULE: Foundry - Outputs
# Mirrors bicep module outputs:
#   - extendedAIServicesConfig
#   - aiFoundryPrincipalIds
# =============================================================================

output "foundry_ids" {
  description = "Resource IDs for each AI Foundry (AIServices) account."
  value       = azapi_resource.foundry[*].id
}

output "foundry_names" {
  description = "Names of each AI Foundry account."
  value       = azapi_resource.foundry[*].name
}

output "foundry_endpoints" {
  description = "Endpoint for each AI Foundry account."
  value = [
    for r in azapi_resource.foundry : try(r.output.properties.endpoint, "")
  ]
}

output "foundry_principal_ids" {
  description = "System-assigned managed identity principal IDs for each Foundry account."
  value = [
    for r in azapi_resource.foundry : try(r.output.identity.principalId, "")
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
    for i, f in azapi_resource.foundry : {
      name                     = f.name
      location                 = var.foundry_instances[i].location
      cognitive_service_id     = f.id
      cognitive_service_name   = f.name
      endpoint                 = try(f.output.properties.endpoint, "")
      foundry_project_endpoint = "https://${f.name}.services.ai.azure.com/api/projects/${azapi_resource.project[i].name}"
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