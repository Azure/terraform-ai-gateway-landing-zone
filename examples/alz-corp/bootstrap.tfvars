# Vending created the workload RG and the two pipeline identities: bootstrap
# only adds the state account and the role assignments.
github                         = { repository = "<owner>/<repo>" }
create_pipeline_identities     = false
create_workload_resource_group = false
existing_pipeline_identities = {
  apply_principal_id = "<vended-apply-principal-id>"
  plan_principal_id  = "<vended-plan-principal-id>"
}
graph_permissions = false # identity stack run by a human / Entra team; entra values set in gateway-config.tfvars

# Network Contributor on the vended VNet (subnets live there).
additional_apply_role_assignments = {
  vended-vnet = {
    scope                      = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>"
    role_definition_id_or_name = "Network Contributor"
  }
}

# Corp: the state account is private too.
state_storage = {
  public_network_access_enabled = false
  private_endpoint = {
    subnet_id = "/subscriptions/<sub>/resourceGroups/<rg-vended-net>/providers/Microsoft.Network/virtualNetworks/<vnet-spoke>/subnets/<snet-cicd-or-pe>"
  }
}
