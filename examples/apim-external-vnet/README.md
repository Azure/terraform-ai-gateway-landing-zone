# APIM Developer, external VNet (classic injection)

Developer-tier APIM injected into `snet-apim` with a **public** VIP: the
gateway stays reachable from the internet while its backends (Foundry, Event
Hub, Key Vault, Cosmos DB) are reached privately through the VNet. This is
the classic "external" mode; use it for non-production tests of the
VNet-injected data path with public callers. Developer has no SLA and one
unit; use Premium (`capacity = 3`, zone redundant) for production.

The network stack creates the NSG rules classic external injection needs
(client traffic on 443 from the internet, management endpoint on 3443 from
the `ApiManagement` service tag, load balancer probes on 6390, and the
outbound Storage, SQL, Azure Monitor and Key Vault dependencies). Optionally
bring your own Standard-SKU public IP (`apim.public_ip_address_id`) to keep
the gateway address stable across re-creations.

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Owner): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here, then every access contract
```

Classic injection is create-time only, and the first apply takes 30 to 60
minutes. A stack runs only if its `<stack>.tfvars` exists, so the files in
this folder define the topology. See `docs/deployment-scenarios.md`.
