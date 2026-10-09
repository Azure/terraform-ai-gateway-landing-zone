# 🏰 AI Gateway Landing Zone — Terraform

Terraform implementation of the [AI Gateway Landing Zone (Bicep)](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1)
solution accelerator, built on [Azure Verified Modules](https://aka.ms/avm) and
split into independently deployable **stacks** that fit an Azure Landing Zone
(CAF) application landing zone.

---

## 📐 Architecture

```text
 environments/<env>/*.tfvars ──► Taskfile (task up / task apply STACK=…) ──► stacks/* (one state each)

  0 bootstrap ──► state account · workload RG · plan + apply pipeline identities (OIDC)
  1 identity  ──► Entra app for JWT validation (no secret)
  2 network   ──► greenfield VNet + subnets + private DNS │ alz_spoke subnets + UDR │ (byo: skipped)
 2b app-hosting ► ILB App Service Environment v3 (keyless usage pipeline)
  3 platform  ──► APIM · Key Vault · Foundry (+ models) · Cosmos DB · Event Hub · Redis · API Center
                  · Log Analytics / App Insights · usage-ingestion Logic App (ASE v3 or WS)
  4 gateway-config ──► named values · shared policy fragments · service APIs · non-LLM backends
  5 llm-backend-onboarding ──► LLM backends + pools (from the Foundry deployments) · routing · LLM APIs
  6 access-contracts (× N) ──► per use case: products · subscriptions · Key Vault secrets · Foundry connection
```

Stacks find each other's resources **by deterministic name** (no remote state):
a change to a policy fragment plans only `gateway-config`; onboarding a use case
touches only its own contract state. Details: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).

```text
┌──────────────────────── rg-<workload>-<env> ───────────────────────────────┐
│  VNet (greenfield, or the vended ALZ spoke)                                 │
│   snet-apim · snet-pe · snet-agent · snet-ase · snet-cicd (· snet-logic)    │
│                                                                             │
│  API Management ──► Foundry (models, PII, Content Safety) · AI Search · MCP │
│      │  usage metrics / events                                              │
│      ▼                                                                      │
│  Event Hub ──► Logic App Standard (ASE v3, keyless) ──► Cosmos DB           │
│  Key Vault · Log Analytics · App Insights · API Center · Managed Redis      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick start

Prerequisites: Terraform (`.terraform-version`), [Task](https://taskfile.dev),
Azure CLI, Owner on a subscription.

```bash
az login && az account set --subscription <subscription-id>

cp -r examples/quickstart environments/dev     # pick a scenario (below)
# edit environments/dev/*.tfvars: replace every <...> placeholder

task bootstrap ENV=dev                          # once: state, workload RG, pipeline identities
task up ENV=dev                                 # every configured stack, then every access contract
task validate ENV=dev                           # post-deploy smoke tests
```

One stack at a time: `task apply STACK=platform ENV=dev`; one use case:
`task contract ENV=dev USE_CASE=team-a-chatbot`; everything read-only:
`task plan-all ENV=dev`; teardown: `task down ENV=dev`. Run `task` for the full list.

### Scenarios ([examples/](examples/), [docs/deployment-scenarios.md](docs/deployment-scenarios.md))

| Scenario | Network | APIM | Usage pipeline | For |
|---|---|---|---|---|
| [quickstart](examples/quickstart/) | greenfield | StandardV2, public + integration | Workflow Standard | demos from a laptop |
| [minimal-dev](examples/minimal-dev/) | greenfield | StandardV2, no VNet | Workflow Standard | cheapest dev |
| [dev-greenfield-private](examples/dev-greenfield-private/) | greenfield + CI runner subnet | StandardV2, integration + PE, public off | ASE v3, keyless | private dev/test without a platform team |
| [byo-hub-spoke-network](examples/byo-hub-spoke-network/) | byo | Developer, internal | Workflow Standard | existing hub-spoke |
| [alz-corp](examples/alz-corp/) | alz_spoke | Premium ×3, internal | ASE v3, keyless | ALZ Corp production |
| [premium-internal-vnet](examples/premium-internal-vnet/) | greenfield | Premium ×3, internal | ASE v3 | classic private VIP |
| [apim-v2-private-endpoint](examples/apim-v2-private-endpoint/) | greenfield | StandardV2, integration + PE | ASE v3 | v2 private |
| [apim-premiumv2-injection](examples/apim-premiumv2-injection/) | greenfield | PremiumV2, injection | ASE v3 | v2 private VIP |
| [dev-greenfield-private-ws](examples/dev-greenfield-private-ws/) | greenfield + CI runner subnet | StandardV2, integration + PE, public off | Workflow Standard, private endpoint | private dev/test, faster than ASE |
| [apim-external-vnet](examples/apim-external-vnet/) | greenfield | Developer, external | Workflow Standard | classic public VIP in a VNet |
| [shared-ase](examples/shared-ase/) | greenfield + extra DNS links | StandardV2, integration + PE | shared ASE v3 | ASE owned by another team |
| [multi-provider-llm](examples/multi-provider-llm/) | greenfield | StandardV2, integration | Workflow Standard | Azure OpenAI, third party, AWS Bedrock |
| [existing-apim-platform](examples/existing-apim-platform/) | byo (name overrides) | existing APIM | not deployed | gateway config on an APIM you run |
| [all-features](examples/all-features/) | greenfield | StandardV2, integration + PE | Workflow Standard | every optional switch, to copy from |

---

## 🔧 Configuration highlights

| Topic | Where | Notes |
|---|---|---|
| Names | `common.tfvars` `workload`, `environment`, `naming` | `<prefix>-<workload>-<env>[-<seed>]`; [modules/naming](modules/naming/README.md) |
| Network model | `common.tfvars` `network_mode`; `network.tfvars` | greenfield / alz_spoke / byo — [DEPLOYMENT_GUIDE §5](DEPLOYMENT_GUIDE.md#5-network-modes) |
| APIM SKU × network | `platform.tfvars` `apim` | none · external · internal · integration · injection — [apim-network-modes.md](docs/operations/apim-network-modes.md) |
| Foundry accounts and models | `platform.tfvars` `foundry` | LLM backends are derived from the deployments in `llm-backend-onboarding` |
| External LLMs, aliases | `llm-backend-onboarding.tfvars` | `extra_llm_backends` (Key Vault-referenced credentials), `model_aliases` |
| Entra JWT auth | `identity.tfvars` + `gateway-config.tfvars` `entra_auth` | the app is looked up by name |
| Usage pipeline | `platform.tfvars` `usage_pipeline` | `ase_v3` (keyless, run-from-package) or `workflow_standard` (shared-key exception) |
| Access contracts | `access-contracts/<use-case>.tfvars` | keys never in state (ephemeral read, write-only secrets) |

Every stack's inputs and outputs are documented in its README
(`stacks/<stack>/README.md`, generated by terraform-docs); see also
[VARIABLES.md](VARIABLES.md).

---

## 🌐 API endpoints (post-deploy)

| API | URL pattern | Use case |
|-----|-------------|---------|
| Universal LLM | `{gateway_url}/models/chat/completions` | Recommended — all models |
| Azure OpenAI compatible | `{gateway_url}/openai/deployments/{model}/chat/completions` | SDK compatibility |
| List models | `GET {gateway_url}/models/` | Discover available models |

```bash
URL=$(task output STACK=llm-backend-onboarding ENV=dev NAME="-raw universal_llm_api_url")
KEY=$(az keyvault secret show --vault-name <key-vault> -n teama-llm-key --query value -o tsv)   # written by the access contract
curl -X POST "$URL/chat/completions" -H "Content-Type: application/json" -H "api-key: $KEY" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello from Citadel!"}]}'
```

---

## 🧪 Validation notebooks

[validation/](validation/) holds the Jupyter notebooks ported from the upstream
accelerator (helpers in [shared/](shared/)). They exercise a **live**
environment: LLM backend onboarding, all-models tests, access contracts and
model aliases. They write tfvars into `environments/<env>/` and deploy through
the stacks. See [validation/README.md](validation/README.md).

```bash
pip install -r shared/requirements.txt
```

---

## 📁 Project structure

```text
├── Taskfile.yml                 # task bootstrap / up / apply / plan-all / contract / down / test / lint
├── stacks/                      # root configurations (own backend, lock file and state)
│   ├── bootstrap/  identity/  network/  app-hosting/  platform/
│   ├── gateway-config/          # + fragments/ (shared) and apis/ (service APIs)
│   ├── llm-backend-onboarding/  # + fragments/ (model-aware) and apis/ (LLM APIs)
│   └── access-contracts/
├── modules/                     # custom modules (call AVM modules, never each other)
├── environments/<env>/          # local, gitignored inputs (only .gitkeep is tracked)
├── examples/<scenario>/         # environment templates to copy
├── logicapp-src/                # usage-ingestion Logic App project
├── scripts/                     # preflight.py (policy check), validate.sh / .ps1, ci/ (repository rules)
├── validation/  shared/         # notebooks and helpers
└── docs/                        # scenarios, operations runbooks
```

Design rules (enforced in CI by `scripts/ci/check-*.sh`): stack → custom module
→ AVM module only; one AVM version per module; identical `variables.common.tf`
and `naming.tf` in every stack; no `terraform_remote_state`; every policy file
has exactly one owner and is wired up.

---

## 📋 Post-deployment checklist

- [ ] `task validate ENV=<env>` — all checks pass
- [ ] `task plan-all ENV=<env>` — no changes
- [ ] Onboard a use case (`access-contracts/<use-case>.tfvars`) and call the gateway with its key
- [ ] Load `model-pricing.json` into the Cosmos DB `model-pricing` container; connect Power BI
- [ ] Production: custom domains + TLS certificates on APIM; GitHub environments with reviewers ([DEPLOYMENT_GUIDE §7](DEPLOYMENT_GUIDE.md#7-cicd-github-actions))

---

## 🔑 Secrets

No secret is passed through tfvars or stored in state: pipelines sign in with
OIDC, the state backend uses Entra ID, APIM subscription keys are read
ephemerally and written only to write-only Key Vault arguments, and backend
credentials are Key Vault references (`auth_config.key_vault_secret_uri`).

---

## 📚 Related documentation

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — stacks, commands, CI/CD, day-2, troubleshooting
- [docs/deployment-scenarios.md](docs/deployment-scenarios.md) — the scenario templates
- [docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md) — what to request from the ALZ platform team
- [docs/operations/apim-network-modes.md](docs/operations/apim-network-modes.md) — APIM network modes and how to change them
- [APIM_POLICY_ARCHITECTURE.md](APIM_POLICY_ARCHITECTURE.md) — policies and fragments
- [CONTRIBUTING.md](CONTRIBUTING.md) — local checks and the rules CI enforces
- Upstream: [AI Citadel Governance Hub](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1) · [LLM routing](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/llm-routing-architecture.md) · [Network approach](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/network-approach.md)

---

## 📄 License

MIT — see [LICENSE](LICENSE)
