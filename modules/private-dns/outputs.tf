output "zone_ids" {
  description = "Logical key => private DNS zone resource ID."
  value       = { for k, m in module.zone : k => m.resource_id }
}
