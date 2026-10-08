# =============================================================================
# Plan-time checks (warnings; they never block an apply)
# =============================================================================

locals {
  deprecated_inputs_set = compact([
    var.cosmos_db_rus != null ? "cosmos_db_rus" : "",
    var.eventhub_partition_count != null ? "eventhub_partition_count" : "",
    var.logic_app_sku_tier != null ? "logic_app_sku_tier" : "",
    var.dns_subscription_id != null ? "dns_subscription_id" : "",
    var.primary_foundry_embedding_model_name != null ? "primary_foundry_embedding_model_name" : "",
    var.language_service_sku != null ? "language_service_sku" : "",
    var.content_safety_sku != null ? "content_safety_sku" : "",
    var.enable_ai_gateway_pii_redaction != null ? "enable_ai_gateway_pii_redaction" : "",
    nonsensitive(var.entra_client_secret != null) ? "entra_client_secret" : "",
    var.azure_monitor_log_settings != null ? "azure_monitor_log_settings" : "",
    var.app_insights_log_settings != null ? "app_insights_log_settings" : "",
  ])
}

check "deprecated_inputs" {
  assert {
    condition     = length(local.deprecated_inputs_set) == 0
    error_message = "These inputs are deprecated and ignored (see the DEPRECATED INPUTS section of variables.tf): ${join(", ", local.deprecated_inputs_set)}. Remove them from your tfvars."
  }
}

check "deprecated_flat_inputs" {
  assert {
    condition     = length([for k, set in local.deprecated_flat_inputs : k if set]) == 0
    error_message = "These flat inputs are deprecated and will be removed in the next major release; move them to the typed objects (interfaces.tf) — old -> new: ${join(", ", [for k, set in local.deprecated_flat_inputs : k if set])}."
  }
}
