# AI Gateway Landing Zone — Deployment Guide

How to deploy and run the gateway: the stack layout, the commands (Task or
plain Terraform), CI/CD, day-2 operations and troubleshooting. The scenario
templates are in [examples/](examples/) and described in
[docs/deployment-scenarios.md](docs/deployment-scenarios.md).

---

## 1. Mental model

The deployment is split into **stacks**: small root configurations, each with
its own state, applied in order. A change in a lower layer never requires
planning a higher one, and a policy edit doesn't refresh Cosmos DB.

| # | Stack | Owns | Typical duration (new env) | Runs when |
|---|---|---|---|---|
| 0 | [bootstrap](stacks/bootstrap/) | State account (one container per stack), workload resource group, plan + apply pipeline identities, their RBAC | 2–3 min | once, by an Owner (`task bootstrap`) |
| 1 | [identity](stacks/identity/) | Entra app APIM validates JWTs against (no client secret) | < 1 min | `identity.tfvars` exists |
| 2 | [network](stacks/network/) | `greenfield`: VNet, subnets, NSGs, private DNS zones. `alz_spoke`: subnets + NSGs + UDR in the vended VNet | 2–5 min | `network.tfvars` exists (not in `byo`) |
| 2b | [app-hosting](stacks/app-hosting/) | ILB App Service Environment v3 + its private DNS zone | **2–4 h** | `app-hosting.tfvars` exists (keyless usage pipeline) |
| 3 | [platform](stacks/platform/) | Identities, monitoring, Key Vault, Cosmos DB, Event Hub, Foundry, Redis, API Center, APIM service + telemetry, usage-ingestion Logic App | 45–90 min (APIM) | always |
| 4 | [gateway-config](stacks/gateway-config/) | Named values, shared policy fragments, non-LLM backends, service APIs, API Center registrations | 5–10 min | always |
| 5 | [llm-backend-onboarding](stacks/llm-backend-onboarding/) | LLM backends and pools (derived from the Foundry deployments), routing and model-aware fragments, LLM APIs, backend credentials | 2–5 min | always |
| 6 | [access-contracts](stacks/access-contracts/) | Per use case: products, subscriptions, Key Vault secrets, Foundry connection — **one state per use case** | ~1 min each | one file per use case |

**How stacks find each other.** Every stack computes the same names from
`workload`, `environment` and `subscription_id` ([modules/naming](modules/naming/)),
and looks up what other stacks own with data sources. There's no
`terraform_remote_state` and nothing to copy between stacks. Only things that
can't be found by name come from tfvars: hub-provided IDs in an ALZ, or the
Entra app values when Graph permissions are kept off the pipeline.

**Two resource groups per environment:** `rg-<workload>-<env>-tfstate` (state
and pipeline identities) and `rg-<workload>-<env>` (everything else). Both are
created by `bootstrap`, so the apply identity's rights stop at the workload
group.

---

## 2. Prerequisites

| Tool | Version | Why |
|---|---|---|
| Terraform | `.terraform-version` (1.16.x) | Stacks pin `~> 1.11`; `tenv`/`tfenv` read the file |
| [Task](https://taskfile.dev) | ≥ 3.40 | `Taskfile.yml`. Install: `brew install go-task` · `winget install Task.Task` · `npm i -g @go-task/cli` |
| Python | ≥ 3.9 (`python3`) | Diagnostic adoption and CI environment restoration helpers (standard library only) |
| Azure CLI | current | Sign-in; `zip_deploy` workflow publishing; `scripts/validate.sh` |
| `gh` (optional) | current | GitHub environments and variables (§7) |

```bash
az login --tenant <tenant-id>
az account set --subscription <workload-subscription-id>
```

Providers use the CLI token locally and OIDC in CI. The state backend uses
Entra ID (`use_azuread_auth = true`), never storage keys.

**Rights.** `task bootstrap` needs **Owner** on the subscription once (it also
registers the resource providers and, with `graph_permissions = true`, grants
Graph app roles — that part needs a Privileged Role Administrator). Afterwards
you act as the **apply identity**: Contributor + RBAC Administrator
(conditioned: no Owner / User Access Administrator / RBAC Administrator) on the
workload group, Storage Blob Data Contributor on the state account, and for
`stacks/identity` Graph `Application.ReadWrite.OwnedBy`.

---

## 3. Environment folder

`environments/<env>/` is the only place where environments differ. Start from a
scenario:

```bash
cp -r examples/dev-greenfield-private environments/dev
# edit environments/dev/*.tfvars: replace every <...> placeholder
```

```text
environments/dev/
├── backend.hcl                    # written by task bootstrap
├── common.tfvars                  # every stack: workload, environment, location, subscription_id, network_mode, naming, tags
├── bootstrap.tfvars               # task bootstrap only
├── identity.tfvars                # present => identity stack runs
├── network.tfvars                 # present => network stack runs (absent for byo)
├── app-hosting.tfvars             # present => ASE v3 (absent for Workflow Standard or a shared ASE)
├── platform.tfvars
├── gateway-config.tfvars
├── llm-backend-onboarding.tfvars
└── access-contracts/
    └── team-a-chatbot.tfvars      # one file = one use case = one state
```

**A stack runs only if its `<stack>.tfvars` exists**, so the folder defines the
topology. All environment files, including `backend.hcl`, are gitignored.
Only `environments/.gitkeep` is checked in. Keep reusable placeholder templates
in `examples/`; keep deployment-specific values locally or in the GitHub
environment secret described in §7.

```hcl
# environments/dev/common.tfvars
workload        = "aigw"          # 2-8 lowercase letters/digits
environment     = "dev"
location        = "swedencentral"
subscription_id = "<workload-subscription-id>"
network_mode    = "greenfield"    # greenfield | alz_spoke | byo
# naming = { unique_seed = "k3x9p", name_overrides = { apim = "apim-contoso-dev" } }
tags            = { workload = "ai-gateway", environment = "dev" }
```

Names follow `<prefix>-<workload>-<env>[-<seed>]`, e.g. `apim-aigw-dev-k3x9p`;
the seed is derived from the subscription, workload and environment unless
`naming.unique_seed` is set. See [modules/naming](modules/naming/README.md).

---

## 4. Deploy

### 4.1 Bootstrap (once per environment)

```bash
task bootstrap ENV=dev
```

Applies `stacks/bootstrap` with local state, writes
`environments/dev/backend.hcl`, migrates the state into the account it just
created, and prints the outputs: `apply_client_id` / `plan_client_id` (for the
GitHub environments, §7) and `apply_principal_id` / `plan_principal_id` (for
`secret_writer_principal_ids` / `secret_reader_principal_ids` in
`platform.tfvars`).

In an ALZ where subscription vending provides the identities and the resource
group, set `create_pipeline_identities = false`,
`create_workload_resource_group = false` and `existing_pipeline_identities` —
bootstrap then only adds the state account and the role assignments.

### 4.2 Whole environment

```bash
task up ENV=dev
```

Applies every configured stack in order, then every access contract. Each step
runs `init` → `plan -out=tfplan` → `apply tfplan`. Check the result:

```bash
task output STACK=platform ENV=dev NAME=apim_gateway_url
task validate ENV=dev          # post-deploy smoke tests (scripts/validate.sh)
task plan-all ENV=dev          # every stack and contract should report "No changes"
```

### Diagnostic settings that already exist

`task apply` (and the notebook helper's plain-Terraform fallback) uses
`scripts/apply-stack.py`. Before apply it checks planned
`azurerm_monitor_diagnostic_setting` creates against Azure. It imports only an
**exact target resource ID + setting name match**, using the provider's
`<resource-id>|<setting-name>` import ID, then replans. It does not adopt a
differently named setting just because it writes to the same workspace.

On a fresh deployment the target ID may be unknown until apply. If apply
fails, the helper replans once to resolve it and checks for an orphaned
diagnostic setting (for example Azure completed the PUT but the connection
was reset, or Policy created the same name). It retries only if a setting
was actually imported, always with a new saved plan. Other failures are
reported, not silently retried. `task plan` / PR plans never import or write state.

Importing transfers ownership to Terraform: later applies may update the
setting, and destroy may delete it. If **Policy must remain the owner**, opt
out before the first apply in `platform.tfvars`:

```hcl
monitoring = {
  policy_managed_diagnostics = ["cosmosdb", "eventhub", "foundry"]
}
```

Supported keys: `apim`, `cosmosdb`, `eventhub`, `foundry`, `logic_app`.
These disable only the Azure Monitor diagnostic settings; APIM loggers and
service/API diagnostics remain enabled. APIM and Event Hub use idempotent ARM
PUTs rather than importable resources; the same opt-out prevents overwriting
policy settings there. Other named policy settings, such as `setByPolicy`,
are never imported or changed by the helper.

For a setting already tracked in Terraform, release it with
`terraform state rm '<address>'` **before** switching its service to
policy-managed; otherwise Terraform will plan to delete its old setting.
Plain `terraform apply` does not run the helper: use
`python3 scripts/apply-stack.py stacks/platform -- -var-file=<common> -var-file=<platform>`
after saving a plan, or import manually.

### 4.3 One stack at a time

Useful the first time, or to stop between layers:

```bash
task apply STACK=identity               ENV=dev
task apply STACK=network                ENV=dev
task apply STACK=app-hosting            ENV=dev   # 2-4 h: run in tmux/screen or CI
task apply STACK=platform               ENV=dev
task apply STACK=gateway-config         ENV=dev
task apply STACK=llm-backend-onboarding ENV=dev
task contract ENV=dev USE_CASE=team-a-chatbot      # or: task contracts ENV=dev
```

`task plan STACK=<stack> ENV=<env>` plans only (`LOCK=-lock=false` for the
read-only plan identity).

### 4.4 Without Task (plain Terraform)

```bash
E=environments/dev
terraform -chdir=stacks/platform init -reconfigure -backend-config=../../$E/backend.hcl
terraform -chdir=stacks/platform plan -out=tfplan -var-file=../../$E/common.tfvars -var-file=../../$E/platform.tfvars
terraform -chdir=stacks/platform apply tfplan

# an access contract: its own state key
terraform -chdir=stacks/access-contracts init -reconfigure -backend-config=../../$E/backend.hcl -backend-config=key=team-a-chatbot.tfstate
terraform -chdir=stacks/access-contracts apply -var-file=../../$E/common.tfvars -var-file=../../$E/access-contracts/team-a-chatbot.tfvars
```

Bootstrap without Task: add a `backend_override.tf` with `backend "local" {}`
to `stacks/bootstrap`, apply, write `backend.hcl` from `terraform output -raw
backend_hcl`, delete the override and run `terraform init -migrate-state
-backend-config=…`.

### 4.5 Reaching private data planes

Some steps talk to private endpoints: the state account (when private), Key
Vault secrets in access contracts, and the workflow package on the keyless
storage account (every plan reads it). Options:

| Option | How | When |
|---|---|---|
| Runner in `snet-cicd` (default) | GitHub-hosted runner with Azure private networking (subnet delegated to `GitHub.Network/networkSettings`), or a self-hosted runner VM (`cicd_subnet_delegation = "none"`) | CI, and every Corp environment |
| `dev_access` (greenfield, non-prod) | `platform.tfvars`: `dev_access = { allowed_cidrs = ["<your-ip>/32"] }` — Key Vault and storage allow those CIDRs (default action stays Deny). A `check` fails for prod or non-greenfield. | Laptop runs |

Behind proxied egress (secure web gateway / SASE) the services see the proxy's
address, which can differ per process — IP allow-listing is unreliable there;
use a runner.

---

## 5. Network modes

The commands are the same in every mode; only the environment folder differs.

| | `greenfield` | `alz_spoke` | `byo` |
|---|---|---|---|
| `network.tfvars` | `address_space` (/22), `apim_vnet_mode`, `subnets_enabled` | `alz_spoke = { vended_vnet_id, hub_firewall_ip }`, `address_space` or `subnet_prefixes` from the vending allocation, `apim_vnet_mode` | absent |
| Private DNS | created by `network` (13 `privatelink.*` zones), looked up by `platform` | hub-owned; DINE binds most zone groups | hub/customer-owned |
| `app-hosting.tfvars` | `ase = {…}` (subnet and VNet looked up) | `ase.subnet_id`, `dns.vnet_link_ids` (spoke + hub/resolver) | `ase.subnet_id`, `dns.vnet_link_ids` |
| `platform.tfvars` `network` | omit (looked up) | `task output STACK=network NAME=platform_network` + hub zone IDs Terraform still binds (openai, ai_services, apim_gateway, redis) | every ID |

`apim_vnet_mode` in `network.tfvars` must equal `apim.vnet_mode` in
`platform.tfvars` (APIM network matrix:
[docs/operations/apim-network-modes.md](docs/operations/apim-network-modes.md)).
There's no in-place move from `greenfield` to `alz_spoke`: deploy a new
`alz_spoke` environment from the same code and move traffic and use cases.
Platform-team requests for an ALZ:
[docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md).

---

## 6. Day-2 operations

| Change | Edit | Command (CI does it on merge) |
|---|---|---|
| Add or change an LLM backend, model alias or credential | `llm-backend-onboarding.tfvars` (`extra_llm_backends`, `model_aliases`, `aws`) | `task apply STACK=llm-backend-onboarding ENV=<env>` |
| New Foundry model deployment | `platform.tfvars` `foundry.models` | `task apply STACK=platform …`, then `STACK=llm-backend-onboarding` (backends are derived from the deployments) |
| Onboard a use case | new `access-contracts/<use-case>.tfvars` | `task contract ENV=<env> USE_CASE=<use-case>` |
| Change a shared fragment or service API | `stacks/gateway-config/fragments/` or `apis/` | `task apply STACK=gateway-config …` |
| Change an LLM API, routing or model-aware fragment | `stacks/llm-backend-onboarding/apis/` or `fragments/` | `task apply STACK=llm-backend-onboarding …` |
| Scale APIM, Foundry capacity, Logic App workers | `platform.tfvars` | `task apply STACK=platform …` |
| Republish only the usage-ingestion workflows | `logicapp-src/usage-ingestion-logicapp/` | `task logic-app-code ENV=<env>` |
| Add a subnet / DNS zone link (greenfield) | `network.tfvars` | `task apply STACK=network …` |

**Entra JWT auth.** `stacks/identity` creates the gateway app;
`gateway-config.tfvars` `entra_auth = { enabled = true }` looks it up by name
and fills the `tenant-id`, `client-id`, `audience`, `entra-auth` and `JWT-*`
named values. `llm-backend-onboarding` reads `entra-auth` and drops the
subscription-key requirement on the LLM APIs. Without Graph permissions on the
pipeline, set `entra_auth.tenant_id` / `client_id` / `audience` explicitly.

**Access contracts and keys.** Subscriptions are created through azapi (APIM
returns no keys on GET); the key is read with an ephemeral `listSecrets` action
and written only to write-only arguments — the Key Vault secret's `value_wo`
and the Foundry connection's `sensitive_body`. Keys are never in state or
outputs; read one from Key Vault, or
`az rest --method post --url "https://management.azure.com<subscription id>/listSecrets?api-version=2024-05-01"`.
They are rewritten every `secret_rotation_days`.

### 6.1 Usage-ingestion workflow code

`usage_pipeline.logic_app.code_deploy = true` publishes
`logicapp-src/usage-ingestion-logicapp` (or `code_source_path`) with the
infrastructure ([modules/logic-app/code-deploy.tf](modules/logic-app/code-deploy.tf)):

| Method | Used by | What runs | Network access the runner needs |
|---|---|---|---|
| `run_from_package` | `ase_v3` default | the zip is uploaded as a content-addressed blob to the keyless account's `deployments` container; the site gets `WEBSITE_RUN_FROM_PACKAGE` + `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID` (usage identity); restart + `syncfunctiontriggers` per new package | the storage blob private endpoint, on **every plan** (the blob is read on refresh) |
| `zip_deploy` | `workflow_standard`; `ase_v3` opt-in | `az functionapp deployment source config-zip` | the site's SCM endpoint (inside the VNet for an ILB ASE) |

Verified live (ASE v3, `run_from_package`): the four workflows load from the
managed-identity-fetched package and a usage event lands in Cosmos DB with key
auth disabled.

---

## 7. CI/CD (GitHub Actions)

| Workflow | Trigger | What it does |
|---|---|---|
| [ci.yml](.github/workflows/ci.yml) | PR, main | fmt, tflint, terraform-docs, repository rules (`scripts/ci/check-*.sh`), checkov, gitleaks, validate + mocked unit tests per module/stack, examples plan against their stacks. No Azure access. |
| [plan.yml](.github/workflows/plan.yml) | PR touching stacks/modules/environments | plans the affected stacks and contracts (`scripts/ci/changed-stacks.sh`) per environment with the **plan** identity; summary in the run; deletes of protected types fail |
| [apply.yml](.github/workflows/apply.yml) | push to main, dispatch | applies the affected stacks in order, dev → test → prod (approvals on the GitHub environments) |
| [drift.yml](.github/workflows/drift.yml) | nightly | `plan -detailed-exitcode` for every stack; opens an issue per drifted environment |
| [e2e.yml](.github/workflows/e2e.yml) | weekly, dispatch | `examples/quickstart` → bootstrap, `task up`, `task validate`, teardown in a sandbox subscription |
| [release.yml](.github/workflows/release.yml) | main | release-please (changelog, tags) |

All of them run Task through [_stack.yml](.github/workflows/_stack.yml).

**Setup per environment** (after `task bootstrap`):

Because environment files are not in the checkout, set the repository
variable `DEPLOYMENT_ENVIRONMENTS` to a JSON array (for example
`["dev","test","prod"]`). An empty/unset list disables deployment discovery.
Store an `ENVIRONMENT_CONFIG_JSON` secret on **both** GitHub environments
`<env>` and `<env>-plan`: a JSON object mapping file paths relative to
`environments/<env>/` to their text contents:

```json
{
  "common.tfvars": "workload = \"aigw\"\n...",
  "backend.hcl": "storage_account_name = \"...\"\n...",
  "platform.tfvars": "apim = {...}\n...",
  "access-contracts/team-a-chatbot.tfvars": "use_case = {...}\n..."
}
```

Include every configured stack's tfvars. The reusable workflow restores only
these input files through `scripts/restore-environment.py`. Updating a secret
does not trigger a Git push; run `apply.yml` manually for configuration-only
changes. The e2e workflow still generates its own inputs from `examples/quickstart`.

```bash
ENV=dev
gh variable set DEPLOYMENT_ENVIRONMENTS --body '["dev","test","prod"]'
gh api -X PUT repos/<owner>/<repo>/environments/$ENV-plan
gh api -X PUT repos/<owner>/<repo>/environments/$ENV
gh variable set AZURE_CLIENT_ID       --env $ENV-plan --body "<plan_client_id>"
gh variable set AZURE_CLIENT_ID       --env $ENV      --body "<apply_client_id>"
for e in $ENV-plan $ENV; do
  gh variable set AZURE_TENANT_ID       --env $e --body "<tenant-id>"
  gh variable set AZURE_SUBSCRIPTION_ID --env $e --body "<workload-subscription-id>"
done
# Generate the JSON object from your local inputs, then:
# gh secret set ENVIRONMENT_CONFIG_JSON --env $ENV      < config.json
# gh secret set ENVIRONMENT_CONFIG_JSON --env $ENV-plan < config.json
# runner that reaches the private data planes (JSON), e.g. a GitHub-hosted runner with private networking:
gh variable set RUNNER_$ENV --body '"aigw-dev-private"'
# prod: add required reviewers and a deployment-branch policy (main) to the "prod" environment
```

The federated credentials trust `repo:<owner>/<repo>:environment:<env>` (apply)
and `…:environment:<env>-plan` (plan). With `pipeline_identity_mode = "single"`
(sandbox/dev only) one identity trusts both.

---

## 8. Tear down

```bash
task down ENV=dev            # contracts, then stacks in reverse order; keeps bootstrap
task destroy STACK=bootstrap ENV=dev   # only when the environment is gone for good
```

Soft-deleted Key Vaults, APIM services and Foundry accounts are purged only
with `purge_soft_delete_on_destroy = true` in `platform.tfvars`, which needs
subscription-level purge rights the pipeline identities don't have — purge as
a human, or keep the names and let `recover_soft_deleted_key_vaults` recover.

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `platform`: `Error: … subnet "snet-pe" … not found` | greenfield, but `stacks/network` hasn't been applied (or the subnet isn't enabled) | apply `network` first; check `subnets_enabled` / `apim_vnet_mode` |
| `platform`: `network_mode alz_spoke / byo: set network …` | the `network` object is missing | `task output STACK=network NAME=platform_network` |
| `gateway-config`: `entra_auth.enabled: the gateway app wasn't found` | `stacks/identity` not applied, or no Graph `Application.Read.All` | apply `identity`, grant the permission, or set the Entra values explicitly |
| `llm-backend-onboarding`: `Missing shared fragments (apply stacks/gateway-config first)` | stacks applied out of order | apply `gateway-config` |
| `llm-backend-onboarding` plans no backends | no Foundry deployments yet, or accounts named outside the naming contract | apply `platform` first, or set `foundry_backends.account_names` |
| `AuthorizationFailure` / `ForbiddenByFirewall` on Key Vault or the package blob | the machine running Terraform can't reach the private data plane | run from a runner in `snet-cicd`, or `dev_access` (greenfield non-prod); behind a proxy use a runner |
| `RequestDisallowedByPolicy` on the Logic App storage account | ALZ `Deny-Storage-Shared-Key` vs Workflow Standard | `usage_pipeline.logic_app.hosting = "ase_v3"` (decision D3) |
| Workflow Standard: workflow publish fails with `504 GatewayTimeout`, the Logic App host reports `ServiceUnavailable`, and every plan wants `allowSharedKeyAccess = false -> true` | tenant or management-group governance turns shared-key access off on storage accounts after they're created (seen in MCAPS tenants); the WS runtime needs the key | use `usage_pipeline.logic_app.hosting = "ase_v3"` (keyless) in that tenant, or get an exemption |
| `ServiceModelDeprecating` on a Foundry deployment | the model version can't take new deployments any more | pick a current version: `az cognitiveservices model list -l <region>` |
| `ForbiddenByFirewall` from Key Vault with a client address you didn't allow-list | proxied egress (secure web gateway / SASE) leaves through a rotating pool of addresses | run from a runner in `snet-cicd`; IP allow-listing doesn't hold behind such a proxy |
| `deny_storage_shared_key needs … "ase_v3"` | precondition in [stacks/platform/policy.tf](stacks/platform/policy.tf) | `hosting = "ase_v3"` or `deny_storage_shared_key = false` |
| APIM v2 with `public_network_access = false` is still public after the first apply | Azure rejects creating a service with public access off | expected: the second apply closes it |
| APIM create sits for 30–60 min; `app-hosting` for 2–4 h | first-time provisioning | normal; don't cancel |
| Logic App runs but the workflows are empty | code publish skipped or failed | `task logic-app-code ENV=<env>` from a runner that reaches the storage PE; fall back to `deployment = "zip_deploy"` |
| `Error acquiring the state lock` in a PR plan | the plan identity can only read state | plans run with `-lock=false` (`LOCK=-lock=false`) |
