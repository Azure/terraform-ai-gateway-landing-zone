# Used once by `task bootstrap` (Contributor + User Access Administrator). Writes backend.hcl next to this file.
github                 = { repository = "<owner>/<repo>" } # null = local runs only (no OIDC credentials)
pipeline_identity_mode = "single"                          # pair (plan + apply) | single (sandbox/dev only)
# false: the pipeline gets no Microsoft Graph rights. Then apply stacks/identity as a person who can
# register applications (task apply STACK=identity), or let scripts/entra_id_setup.py create the app,
# and set entra_auth explicitly in gateway-config.tfvars. true needs a Privileged Role Administrator.
graph_permissions = false
