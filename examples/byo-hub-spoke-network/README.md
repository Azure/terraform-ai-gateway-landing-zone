# BYO hub-spoke network

The network team owns the VNet, subnets and private DNS (no `network.tfvars`,
so the network stack is skipped). `platform.tfvars` carries every ID;
Terraform still binds the zone groups (no DINE policy).

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
