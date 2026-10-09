# Used once by `task bootstrap` (Owner). Writes backend.hcl next to this file.
github                 = { repository = "<owner>/<repo>" } # null = local runs only (no OIDC credentials)
pipeline_identity_mode = "pair"                            # pair (plan + apply) | single (sandbox/dev only)
graph_permissions      = false                             # no identity stack here

# The usage App Service plan joins the shared ASE: the apply identity needs
# Microsoft.Web/hostingEnvironments/join/action on it. Contributor scoped to the ASE
# is the simplest grant; replace it with a custom role holding only that action.
additional_apply_role_assignments = {
  shared-ase = {
    scope                      = "/subscriptions/<sub>/resourceGroups/<rg-ase>/providers/Microsoft.Web/hostingEnvironments/<ase-name>"
    role_definition_id_or_name = "Contributor"
  }
}
