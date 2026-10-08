# Dev, greenfield, fully private

Everything private in a VNet this repository owns (no platform-team
dependency): greenfield VNet, subnets and all `privatelink.*` zones; APIM
StandardV2 with outbound integration and an inbound private endpoint (public
access off); keyless usage pipeline on an ILB ASE v3 (run-from-package);
Entra JWT auth from the identity stack; a CI runner subnet (`snet-cicd`) for
a GitHub-hosted runner with Azure private networking. Apply from that runner
(repository variable `RUNNER_<env>`); a laptop can't reach the private data
planes.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
