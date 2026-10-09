# Dev, greenfield, private (Workflow Standard Logic App)

The same shape as `dev-greenfield-private`, but the usage pipeline runs on a
**Workflow Standard** plan instead of an ASE v3 (hours faster to create and no
ASE cost), reached through a private endpoint:

- greenfield VNet, subnets and every `privatelink.*` zone, including
  `privatelink.azurewebsites.net` (`network.tfvars` `private_dns.logic_app_zone`);
- APIM StandardV2 with outbound VNet integration and an inbound private
  endpoint (public access off after the second apply);
- Logic App `sites` private endpoint with the public website/SCM closed
  (`usage_pipeline.logic_app.private_endpoint` and `public_network_access`);
- a CI runner subnet (`snet-cicd`) for a GitHub-hosted runner with Azure
  private networking.

Workflow Standard needs shared-key storage. If your tenant enforces
`allowSharedKeyAccess = false` by policy, use the ASE v3 variant
(`dev-greenfield-private`) instead. Publishing the workflows goes through the
private SCM endpoint, so apply from that runner (repository variable
`RUNNER_<env>`); a laptop can't reach it. Set `public_network_access = true`
in `platform.tfvars` for the first apply if you must bootstrap from outside.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md` and
DEPLOYMENT_GUIDE.md section 6.2.
