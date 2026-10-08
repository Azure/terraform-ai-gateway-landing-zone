locals {
  stack                  = "app-hosting"
  foundry_instance_names = []
  greenfield             = var.network_mode == "greenfield"
}
