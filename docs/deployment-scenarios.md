# Deployment scenarios

Each folder in [examples/](../examples/) is a complete environment folder: copy
it to `environments/<env>/`, replace the `<...>` placeholders and run
`task bootstrap ENV=<env>` then `task up ENV=<env>`. A stack runs only when its
`<stack>.tfvars` is present, so the files themselves define the topology. CI
plans every example against its stacks (`scripts/ci/check-examples.sh`), so they
stay valid as the stacks evolve.

| Scenario | `network_mode` | Stacks | APIM | Usage pipeline | Identity / auth | Runs from |
|---|---|---|---|---|---|---|
| [quickstart](../examples/quickstart/) | greenfield | network, platform, gateway-config, llm, 1 contract | StandardV2, integration, public | Workflow Standard (shared-key exception) | single pipeline identity; subscription keys | laptop (`dev_access`) |
| [minimal-dev](../examples/minimal-dev/) | greenfield | network, platform, gateway-config, llm | StandardV2, no VNet, no PE | Workflow Standard | single identity; keys | laptop (`dev_access`) |
| [dev-greenfield-private](../examples/dev-greenfield-private/) | greenfield (+ `snet-cicd`) | all, incl. identity and app-hosting | StandardV2, integration + PE, public off | ASE v3, keyless, run-from-package, Deny shared key | plan + apply identities; Entra JWT | runner in `snet-cicd` |
| [byo-hub-spoke-network](../examples/byo-hub-spoke-network/) | byo | platform, gateway-config, llm | Developer, internal | Workflow Standard | pair; keys | runner with VNet access |
| [alz-corp](../examples/alz-corp/) | alz_spoke | network, app-hosting, platform, gateway-config, llm, contract | Premium ×3 (zones), internal | ASE v3 ×2 workers, zone redundant | vended identities; Entra JWT (explicit values) | private runner |
| [premium-internal-vnet](../examples/premium-internal-vnet/) | greenfield | network, app-hosting, platform, gateway-config, llm | Premium ×3, internal | ASE v3 | pair; keys | runner in `snet-cicd` |
| [apim-v2-private-endpoint](../examples/apim-v2-private-endpoint/) | greenfield | same | StandardV2, integration + PE, public off | ASE v3 | pair; keys | runner in `snet-cicd` |
| [apim-premiumv2-injection](../examples/apim-premiumv2-injection/) | greenfield | same | PremiumV2, injection (private VIP) | ASE v3 | pair; keys | runner in `snet-cicd` |
| [dev-greenfield-private-ws](../examples/dev-greenfield-private-ws/) | greenfield (+ `snet-cicd`, `privatelink.azurewebsites.net`) | network, platform, gateway-config, llm, 1 contract | StandardV2, integration + PE, public off | Workflow Standard with `sites` private endpoint, public off | pair; keys | runner in `snet-cicd` |
| [apim-external-vnet](../examples/apim-external-vnet/) | greenfield | network, platform, gateway-config, llm, 1 contract | Developer, external (public VIP) | Workflow Standard | single identity; keys | laptop (`dev_access`) |
| [shared-ase](../examples/shared-ase/) | greenfield (+ extra DNS links) | network, platform, gateway-config, llm, 1 contract | StandardV2, integration + PE, public off | ASE v3 owned by another team (`ase.app_service_environment_id`) | pair; keys | runner in `snet-cicd` |
| [multi-provider-llm](../examples/multi-provider-llm/) | greenfield | network, platform, gateway-config, llm, 1 contract | StandardV2, integration | Workflow Standard | single identity; keys | laptop (`dev_access`) |
| [existing-apim-platform](../examples/existing-apim-platform/) | byo (name overrides) | gateway-config, llm, 1 contract | an APIM you already run | none (not deployed) | pair; Entra JWT (explicit values) | runner with APIM access |
| [no-foundry-ai-services](../examples/no-foundry-ai-services/) | greenfield | network, platform, gateway-config, llm, 1 contract | StandardV2, integration | Workflow Standard | single identity; keys | laptop (`dev_access`) |
| [all-features](../examples/all-features/) | greenfield (+ AMPLS zone, extra DNS links) | all but app-hosting, incl. identity | StandardV2, integration + PE | Workflow Standard | pair; Entra JWT | runner in `snet-cicd` |

## Choosing

- **Demo or first look:** `quickstart`. **Cheapest dev:** `minimal-dev`.
- **Private dev/test without a platform team:** `dev-greenfield-private` (ASE v3,
  keyless, hours to create) or `dev-greenfield-private-ws` (Workflow Standard
  with a private endpoint, faster, needs shared-key storage). The VNet isn't
  connected to a hub, so neither is for Corp.
- **Azure Landing Zone (Corp):** `alz-corp`. Request the vended spoke, hub DNS
  and identities first ([platform-team-requests.md](operations/platform-team-requests.md)).
  In Corp, APIM v2 SKUs need an `Enforce-GR-APIM` exemption; classic Premium
  `internal` doesn't.
- **Existing hub-spoke owned by a network team:** `byo-hub-spoke-network`.
- **An ASE someone else runs:** `shared-ase`.
- **An APIM service you already have:** `existing-apim-platform` (gateway
  configuration only).
- **Several model providers (Azure OpenAI, third party, AWS Bedrock):**
  `multi-provider-llm`.
- **No Foundry accounts, but PII redaction and content safety:**
  `no-foundry-ai-services` (standalone Language and Content Safety accounts,
  models from `extra_llm_backends`).
- **Every optional switch in one place (to copy from):** `all-features`.
- **APIM network variants:** `apim-v2-private-endpoint`,
  `apim-premiumv2-injection`, `premium-internal-vnet` and `apim-external-vnet`;
  the matrix is in [apim-network-modes.md](operations/apim-network-modes.md).

## Placeholders

| Placeholder | Where to get it |
|---|---|
| `<workload-subscription-id>` | `az account show --query id -o tsv` |
| `<owner>/<repo>` | the GitHub repository whose workflows deploy (OIDC subject); `github = null` for local runs |
| `<your-public-ip>`, `<your-object-id>` | `curl -s https://api.ipify.org`; `az ad signed-in-user show --query id -o tsv` |
| `<apply-principal-id>`, `<plan-principal-id>` | `task output STACK=bootstrap ENV=<env>` (`apply_principal_id`, `plan_principal_id`) |
| vended / hub IDs (`alz-corp`, `byo`) | the platform or network team; `task output STACK=network NAME=platform_network` prints the spoke part for `alz_spoke` |
| `<tenant-id>`, `<gateway-app-client-id>` | `task output STACK=identity ENV=<env>`, or the Entra team when Graph is kept off the pipeline |
| existing resources (`existing-apim-platform`, `shared-ase`, `multi-provider-llm`: `<existing-apim-name>`, `<ase-name>`, `<team-kv>`, `<aoai-resource>`, ...) | the team that owns them; each README lists what the identities need on them |

## Promoting between scenarios

There's no in-place move from `greenfield` to `alz_spoke` (the VNet and DNS
zones change owner), nor between Workflow Standard and ASE v3 storage modes.
Deploy the target scenario as a new environment from the same code, then move
use cases (copy their `access-contracts/*.tfvars`) and traffic across.
