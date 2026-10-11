# AI Gateway Landing Zone — Quick Start

The shortest path to a working gateway: the [quickstart](examples/quickstart/)
scenario (greenfield network, public APIM StandardV2, usage pipeline on
Workflow Standard, one Foundry model, one access contract). For anything else,
see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) and
[docs/deployment-scenarios.md](docs/deployment-scenarios.md).

## Prerequisites

- Terraform (version in `.terraform-version`), [Task](https://taskfile.dev) ≥ 3.40, Azure CLI
- Azure rights per stack, see [Permissions](#permissions)
- A region with quota for APIM StandardV2 and your Foundry model (examples use `swedencentral`)

## 1 — Sign in

```bash
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
```

## 2 — Create the environment folder

```bash
cp -r examples/quickstart environments/dev
```

Replace the placeholders:

| File | Placeholder | Value |
|---|---|---|
| `common.tfvars` | `<workload-subscription-id>` | the subscription ID |
| `bootstrap.tfvars` | `<owner>/<repo>` | your GitHub repository, or `github = null` for laptop-only runs |
| `platform.tfvars` | `<your-public-ip>` | `curl -s https://api.ipify.org` (Key Vault / storage firewalls) |
| `platform.tfvars` | `<your-object-id>` | `az ad signed-in-user show --query id -o tsv` |

Change `workload` / `location` in `common.tfvars` if you like; the model list is
in `platform.tfvars` (`foundry.models`).

## 3 — Deploy

```bash
task bootstrap ENV=dev     # ~3 min: state account, rg-aigw-dev, pipeline identity; writes backend.hcl
task up ENV=dev            # preflight (Azure Policy), then ~60 min: network → platform → gateway-config → llm-backend-onboarding → contract
```

Behind a customer policy set (e.g. the Microsoft cloud security benchmark with
Deny effects) run `task preflight ENV=dev` first; it reports known policy
blockers before anything is deployed (see
[docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md)).

`task up` skips stacks without a tfvars file (the quickstart has no
`identity.tfvars` or `app-hosting.tfvars`).

## 4 — Verify

```bash
task validate ENV=dev                                     # smoke tests (scripts/validate.sh)
KV=$(task output STACK=platform ENV=dev NAME="-raw key_vault_name")
URL=$(task output STACK=llm-backend-onboarding ENV=dev NAME="-raw universal_llm_api_url")
KEY=$(az keyvault secret show --vault-name "$KV" -n teama-llm-key --query value -o tsv)   # written by the access contract
curl -s -X POST "$URL/chat/completions" -H "Content-Type: application/json" -H "api-key: $KEY" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello"}]}'
```

## 5 — Tear down

```bash
task down ENV=dev                      # contracts and stacks, reverse order
task destroy STACK=bootstrap ENV=dev   # state account and identities (last)
```

## Permissions

**Owner is not needed.** Contributor can't write role assignments or role
definitions, so the person running `bootstrap` needs **User Access
Administrator** next to it; nothing else in Owner is used.

Running everything from a laptop (this guide) needs only the two subscription
roles in the first row: they cover every other row. In CI, `bootstrap` gives the
apply identity the "workload resource group" rights below, so the pipeline never
holds subscription-wide rights.

| Stack | Run by | Azure rights | Entra ID |
|---|---|---|---|
| `bootstrap` | a person, once | **Contributor + User Access Administrator** on the subscription (creates the two resource groups, registers resource providers, assigns roles, creates the plan role) | Only with `graph_permissions = true`: Privileged Role Administrator (grants the Graph app roles); the quickstart sets it to `false` |
| `identity` | apply identity | none | Graph `Application.ReadWrite.OwnedBy` (a person: permission to register apps) |
| `network` | apply identity | Contributor on the workload resource group; `alz_spoke`: Network Contributor on the vended VNet | none |
| `app-hosting` | apply identity | Contributor on the workload resource group | none |
| `platform` | apply identity | Contributor, RBAC Administrator (conditioned: no privileged roles) and Resource Policy Contributor on the workload resource group; a shared ASE: `Microsoft.Web/hostingEnvironments/join/action` on it | none |
| `gateway-config` | apply identity | Contributor on the workload resource group | Graph `Application.Read.All`, only with `entra_auth` enabled and no explicit `client_id` |
| `llm-backend-onboarding` | apply identity | Contributor on the workload resource group | none |
| `access-contracts` | apply identity | Contributor on the workload resource group; *Key Vault Secrets Officer* on the platform Key Vault (granted by `platform` through `secret_writer_principal_ids`) | none |

Every stack also needs *Storage Blob Data Contributor* on the state account
(`bootstrap` grants it). The plan identity gets read-only rights only; see
[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) and
[docs/operations/platform-team-requests.md](docs/operations/platform-team-requests.md)
when a platform team issues them.
