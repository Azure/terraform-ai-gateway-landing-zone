# Used once by `task bootstrap` (Owner). Writes backend.hcl next to this file.
github                 = { repository = "<owner>/<repo>" } # null = local runs only (no OIDC credentials)
pipeline_identity_mode = "single"                          # pair (plan + apply) | single (sandbox/dev only)
graph_permissions      = false                             # no identity stack here (Graph app roles need a Privileged Role Administrator)
