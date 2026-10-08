locals {
  stack = "gateway-config"
  # Only the primary Foundry account (PII / Content Safety endpoint) is needed here.
  foundry_instance_names = [var.foundry_primary_account_name]
}
