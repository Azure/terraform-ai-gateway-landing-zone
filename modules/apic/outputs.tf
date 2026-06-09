output "api_center_id" {
  value = var.enable_api_center ? azapi_resource.api_center[0].id : ""
}

output "api_center_name" {
  value = var.enable_api_center ? azapi_resource.api_center[0].name : ""
}
