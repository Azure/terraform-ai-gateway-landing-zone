# Same in every stack: the naming contract (modules/naming) lets each stack
# find what other stacks own by name, without reading their state.
module "naming" {
  source = "../../modules/naming"

  workload               = var.workload
  environment            = var.environment
  subscription_id        = var.subscription_id
  unique_seed            = var.naming.unique_seed
  name_overrides         = var.naming.name_overrides
  foundry_instance_names = local.foundry_instance_names
}

locals {
  names = module.naming.names
  # tflint-ignore: terraform_unused_declarations # APIM-child-only stacks create no taggable resources
  tags = merge({
    workload    = var.workload
    environment = var.environment
    stack       = local.stack
    managed-by  = "terraform"
  }, var.tags)
}
