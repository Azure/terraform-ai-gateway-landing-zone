output "api_ids" {
  description = "API name => API Center API resource ID."
  value       = { for k, a in azapi_resource.apic_api : k => a.id }
}
