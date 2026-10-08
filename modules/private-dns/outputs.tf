output "zone_ids" {
  description = <<-EOT
    Zone key (snake_case) => private DNS zone resource ID.
    Created zones first, then existing_zone_ids (camelCase keys normalised to
    snake_case) on top, so a partial BYO set overrides individual created zones.
  EOT
  value       = local.zone_ids

  precondition {
    condition     = length(setsubtract(var.required_zone_keys, keys(local.zone_ids))) == 0
    error_message = "Private DNS zone IDs are missing for: ${join(", ", setsubtract(var.required_zone_keys, keys(local.zone_ids)))}. Supply them in network.private_dns.zone_ids (or leave private_dns empty to create the zones)."
  }
}
