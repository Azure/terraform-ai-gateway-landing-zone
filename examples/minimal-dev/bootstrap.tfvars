# Used once by `task bootstrap` (Owner). Writes backend.hcl next to this file.
github                 = { repository = "<owner>/<repo>" } # null = local runs only (no OIDC credentials)
pipeline_identity_mode = "single"                          # pair (plan + apply) | single (sandbox/dev only)
