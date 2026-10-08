# Two pipeline identities per environment (D13): a read-only plan identity for
# PR plans and drift checks, and an apply identity for every stack on main.
# GitHub Actions signs in with OIDC (federated credentials, no secrets).
locals {
  plan_environment  = try(coalesce(var.github.plan_environment, "${var.environment}-plan"), null)
  apply_environment = try(coalesce(var.github.apply_environment, var.environment), null)

  identities = var.pipeline_identity_mode == "single" ? {
    apply = { name = local.names.pipeline_apply, github_environments = compact([local.apply_environment, local.plan_environment]) }
    } : {
    plan  = { name = local.names.pipeline_plan, github_environments = compact([local.plan_environment]) }
    apply = { name = local.names.pipeline_apply, github_environments = compact([local.apply_environment]) }
  }

  apply_principal_id = var.create_pipeline_identities ? module.pipeline_identity["apply"].principal_id : var.existing_pipeline_identities.apply_principal_id
  plan_principal_id = var.create_pipeline_identities ? (
    var.pipeline_identity_mode == "pair" ? module.pipeline_identity["plan"].principal_id : local.apply_principal_id
  ) : coalesce(var.existing_pipeline_identities.plan_principal_id, local.apply_principal_id)
  separate_plan_identity = var.create_pipeline_identities ? var.pipeline_identity_mode == "pair" : try(var.existing_pipeline_identities.plan_principal_id, null) != null
}

module "pipeline_identity" {
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "0.5.3"
  for_each = var.create_pipeline_identities ? local.identities : {}

  name                = each.value.name
  location            = var.location
  resource_group_name = module.state_resource_group.name
  tags                = local.tags
  enable_telemetry    = var.enable_telemetry

  federated_identity_credentials = var.github == null ? {} : {
    for ge in each.value.github_environments : ge => {
      name     = "github-${replace(ge, "/[^A-Za-z0-9-]/", "-")}"
      issuer   = "https://token.actions.githubusercontent.com"
      audience = ["api://AzureADTokenExchange"]
      subject  = "repo:${var.github.repository}:environment:${ge}"
    }
  }
}
