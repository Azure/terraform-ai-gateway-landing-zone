# AI Gateway Landing Zone — Quick Start

The shortest path to a working gateway: the [quickstart](examples/quickstart/)
scenario (greenfield network, public APIM StandardV2, usage pipeline on
Workflow Standard, one Foundry model, one access contract). For anything else,
see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) and
[docs/deployment-scenarios.md](docs/deployment-scenarios.md).

## Prerequisites

- Terraform (version in `.terraform-version`), [Task](https://taskfile.dev) ≥ 3.40, Azure CLI
- **Owner** on the target subscription (bootstrap assigns roles and registers resource providers)
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
task up ENV=dev            # ~60 min: network → platform → gateway-config → llm-backend-onboarding → contract
```

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
