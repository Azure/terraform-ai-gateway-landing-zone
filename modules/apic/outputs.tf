output "api_center_id" {
  description = "Resource ID of the API Center service (empty when disabled)."
  value       = var.enable_api_center ? azapi_resource.api_center[0].id : ""
}

output "api_center_name" {
  description = "Name of the API Center service (empty when disabled)."
  value       = var.enable_api_center ? azapi_resource.api_center[0].name : ""
}

output "remote_mcp_server_apis" {
  description = "Remote MCP server name => resource ID of its API Center API."
  value       = { for k, a in azapi_resource.api_center_mcp_api : k => a.id }
}
