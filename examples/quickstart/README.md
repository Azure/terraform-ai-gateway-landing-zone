# Quickstart (Sandbox, public endpoints)

Fastest end-to-end demo from a laptop: greenfield VNet and private DNS, APIM
StandardV2 with public access, the usage pipeline on Workflow Standard (the
documented shared-key exception, so no 2-4 h ASE), one Foundry account with a
small model, one access contract. Not for Corp landing zones.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
