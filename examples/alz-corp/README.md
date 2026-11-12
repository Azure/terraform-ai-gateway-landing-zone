# Azure Landing Zone, Corp (production)

## Scenario Overview
Application landing zone under the Corp management group. Subscription
vending provides the spoke VNet (peered, UDR to the hub firewall), the
workload resource group and the two pipeline identities; the hub owns the
`privatelink.*` zones and the ALZ `Deploy-Private-DNS-Zones` policy binds
most of them. This repository adds subnets + NSGs + UDRs (`alz_spoke`), the
ILB ASE v3, Premium APIM with classic internal VNet injection, and keyless
services only. Runs from a private runner. Platform-team requests:
`docs/operations/platform-team-requests.md`.

Monitoring is private: the App Insights components join the hub's Azure
Monitor Private Link Scope (`monitoring.existing_private_link_scope_id`; the
apply identity gets Monitoring Contributor on it in `bootstrap.tfvars`) and
accept telemetry only through it. Public query is closed on the Logic App and
Foundry components and stays on the APIM component, which the usage
pipeline's Logic App connector reads through Resource Manager. The central
workspace keeps the platform team's settings, but must accept public queries:
the APIM component's data lives there, and a closed workspace returns the
connector's queries empty (the usage export then silently exports nothing).
The APIM and Logic App components also accept only managed identity ingestion
(`monitoring.app_insights_entra_ingestion`, the default): the APIM logger and
the Logic App runtime send as their identities (Monitoring Metrics Publisher),
so the instrumentation key alone can't send telemetry. The loggers' credentials
are Key Vault secrets read through Key Vault-backed named values
(`apim_logging.credentials_in_key_vault`, the default), so APIM holds no secret
named values of its own ("API Management secret named values should be stored in
Azure Key Vault").
A hub-and-spoke that shares DNS takes one scope (the hub's): a second one
would overwrite the hub's records.

## Prerequisites

### Tools
On the machine that runs Terraform (the private runner, see below):

| Tool | Version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | [`.terraform-version`](../../.terraform-version) (1.16.x) | `tenv`/`tfenv`, or the release zip |
| [Task](https://taskfile.dev) | ≥ 3.40 | `brew install go-task` · `sh -c "$(curl -L https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin` |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | current | `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` |
| Python 3 | ≥ 3.9 | `scripts/preflight.py`, `scripts/entra_id_setup.py` (standard library only) |
| `git`, `jq`, `zip`, `rsync`, `curl` | any | Logic App packaging, `scripts/validate.sh` |

On your workstation (only to create the platform simulation below): Azure CLI with the
`azure-firewall` extension, `ssh`, `rsync`.

### Permissions
- **Bootstrap**: Contributor + User Access Administrator (or Owner) on the workload subscription.
- **Stacks**: the apply identity's roles that `stacks/bootstrap` grants (or the same person).
- **Entra ID**: rights to register applications (`graph_permissions = false`: the gateway app is created
  by a person with `task entra-setup`, not by the pipeline).

### Platform (landing zone) inputs
Everything outside the workload resource group comes from the platform team
([`platform-team-requests.md`](../../docs/operations/platform-team-requests.md)). Each `<...>` placeholder in
this folder maps to one of them:

| Placeholder | What it is | Request | Used in |
|---|---|---|---|
| `<workload-subscription-id>`, `<sub>` | Vended application landing zone subscription (Corp MG) | P1 | `common.tfvars`, every ID |
| `<rg-vended-net>/<vnet-spoke>` | Vended spoke VNet, peered to the hub, with ≥ /22 free for this workload (`network.tfvars` `address_space`) | P2 | `network`, `app-hosting`, `platform`, `bootstrap` |
| `<snet-cicd-or-pe>` | A **pre-existing** vended subnet for the state account private endpoint (bootstrap runs before `stacks/network` creates `snet-cicd`) | P2 / P8 | `bootstrap.tfvars` |
| `<hub-firewall-private-ip>` | Hub Azure Firewall / NVA private IP (UDR next hop), allowing the APIM, ASE v3, Foundry and runner egress | P5 | `network.tfvars` |
| `<hub-sub>/<rg-dns>` zones | `privatelink.*` zones, resolvable from the spoke | P3 | `platform.tfvars` `network.private_dns_zone_ids` |
| `<hub-sub>/<rg-hub>/<vnet-hub-or-resolver>` | Hub / resolver VNet that the ASE zone links to | P3 / P4 | `app-hosting.tfvars`, `bootstrap.tfvars` |
| `<mgmt-sub>/<rg-mgmt>/<law>` | Central Log Analytics workspace (accepts public queries) | P11 | `platform.tfvars`, `bootstrap.tfvars` |
| `<hub-sub>/<rg-hub-monitor>/<ampls-hub>` | Hub Azure Monitor Private Link Scope | P11 | `platform.tfvars`, `bootstrap.tfvars` |
| `<vended-apply-principal-id>`, `<vended-plan-principal-id>` | Principal IDs of the vended pipeline identities | P7 | `bootstrap.tfvars`, `platform.tfvars` |
| `<owner>/<repo>` | GitHub repository for OIDC federation (`github = null` for runner-only runs) | P7 | `bootstrap.tfvars` |
| `<tenant-id>`, `<gateway-app-client-id>` | Entra tenant and gateway app registration (`task entra-setup`, below) | – | `gateway-config.tfvars` |

Also from the platform: a **private runner** in the spoke (P8: the state account, Key Vault and the Logic
App storage are private; the runner must reach their private endpoints), firewall rules (P5), and the
APIM per-hostname DNS records `<apim>.azure-api.net`, `.portal.`, `.developer.`, `.management.`, `.scm.` →
the APIM private IP once `stacks/platform` has created APIM (P3).

### No landing zone? Simulate the platform
To try the scenario in a sandbox subscription, the commands below build the platform pieces in the
workload subscription itself (connectivity, management and vending all simulated):

| Resource group | Simulates | Contents |
|---|---|---|
| `rg-alzsim-hub` | Connectivity hub | Hub VNet `10.0.0.0/22`, Azure Firewall **Basic** + policy (spoke egress, DNAT `:2222` → runner SSH) |
| `rg-alzsim-dns` | Hub DNS | 17 `privatelink.*` zones + 5 APIM per-hostname zones, each linked to the hub **and** the spoke (instead of a DNS resolver) |
| `rg-alzsim-hub-monitor` | Hub monitoring | Azure Monitor Private Link Scope + its private endpoint in the hub |
| `rg-alzsim-mgmt` | Management | Central Log Analytics workspace |
| `rg-alzsim-<env>-net` | Vending | Spoke VNet `10.20.0.0/21` peered to the hub; `snet-runner` `10.20.0.0/26` (UDR → firewall); `10.20.4.0/22` left for `stacks/network` |
| `rg-alzsim-<env>-identity` | Vending | `id-tf-<workload>-<env>-plan` / `-apply` user-assigned identities |
| `rg-alzsim-<env>-runner` | Private runner | Ubuntu VM `10.20.0.4` (no public IP) with Terraform, Task, Azure CLI; apply identity attached |
| `rg-<workload>-<env>` | Vending | Empty workload resource group (`create_workload_resource_group = false`) |

There is no ALZ policy in the simulation, so the environment differs from a real Corp landing zone in four
settings (each commented in the `.tfvars`): `network.dns_zone_groups_managed_by_policy = false` with every
zone in `network.private_dns_zone_ids`, `monitoring.policy_managed_diagnostics = []`,
`deny_storage_shared_key = true`, and `state_storage.private_endpoint.private_dns_zone_id` set. The apply
identity also gets *Private DNS Zone Contributor* on the zones and *Log Analytics Contributor* on the
workspace (`additional_apply_role_assignments`).

> Cost: Azure Firewall Basic and the runner VM are the simulation's fixed costs; the gateway itself
> (APIM Premium, ASE v3, Azure Managed Redis) is far larger. Delete everything when done ([Clean up](#clean-up)).

Run from the repository root (bash or zsh), signed in with `az login` as an Owner of the subscription.

**1. Variables** (re-run this block in every new shell, including on the runner):

```bash
SUB=<workload-subscription-id>              # workload subscription (also hosts the simulated hub)
LOC=swedencentral
SIM=alzsim                                  # prefix of the simulated platform resources
WORKLOAD=aigw                               # = workload in common.tfvars
ENV_CODE=alzcorp01                          # = environment in common.tfvars (2-10 lowercase letters/digits)
MY_IP=$(curl -s https://api.ipify.org)      # your public IP (SSH to the runner through the firewall DNAT)

RG_HUB=rg-$SIM-hub                 # connectivity: hub VNet + firewall
RG_DNS=rg-$SIM-dns                 # connectivity: private DNS zones
RG_MON=rg-$SIM-hub-monitor         # connectivity: Azure Monitor Private Link Scope
RG_MGMT=rg-$SIM-mgmt               # management: central Log Analytics workspace
RG_NET=rg-$SIM-$ENV_CODE-net       # vended: spoke VNet
RG_ID=rg-$SIM-$ENV_CODE-identity   # vended: pipeline identities
RG_RUNNER=rg-$SIM-$ENV_CODE-runner # private runner VM
RG_WL=rg-$WORKLOAD-$ENV_CODE       # vended: workload resource group (naming contract rg-<workload>-<environment>)

HUB_VNET=vnet-$SIM-hub
SPOKE_VNET=vnet-$SIM-$ENV_CODE-spoke
FW=afw-$SIM-hub
LAW=log-$SIM-mgmt
AMPLS=ampls-$SIM-hub
TAGS=(Workload=ai-gateway Environment=$ENV_CODE SecurityControl=ignore Purpose=alz-platform-simulation)
# APIM name of the naming contract: apim-<workload>-<environment>-<first 5 hex of sha256("<sub>/<workload>/<environment>")>
APIM_NAME=apim-$WORKLOAD-$ENV_CODE-$(printf '%s' "$SUB/$WORKLOAD/$ENV_CODE" | shasum -a 256 | cut -c1-5)

az account set --subscription $SUB
```

**2. Hub network, firewall, workspace and AMPLS** (~15 minutes, mostly the firewall):

```bash
# --- Resource groups ---------------------------------------------------------
for rg in $RG_HUB $RG_DNS $RG_MON $RG_MGMT $RG_NET $RG_ID $RG_RUNNER $RG_WL; do
  az group create -n $rg -l $LOC --tags "${TAGS[@]}" -o none
done

# --- Hub VNet (connectivity) ---------------------------------------------------
az network vnet create -g $RG_HUB -n $HUB_VNET -l $LOC --address-prefixes 10.0.0.0/22 --tags "${TAGS[@]}" -o none
az network vnet subnet create -g $RG_HUB --vnet-name $HUB_VNET -n AzureFirewallSubnet           --address-prefixes 10.0.0.0/26  -o none
az network vnet subnet create -g $RG_HUB --vnet-name $HUB_VNET -n AzureFirewallManagementSubnet --address-prefixes 10.0.0.64/26 -o none
az network vnet subnet create -g $RG_HUB --vnet-name $HUB_VNET -n snet-hub-pe                   --address-prefixes 10.0.1.0/26  --default-outbound-access false -o none

# --- Vended spoke VNet: 10.20.0.0/21 = snet-runner (vending) + 10.20.4.0/22 (workload carve, network.tfvars address_space)
az network vnet create -g $RG_NET -n $SPOKE_VNET -l $LOC --address-prefixes 10.20.0.0/21 --tags "${TAGS[@]}" -o none
HUB_VNET_ID=$(az network vnet show -g $RG_HUB -n $HUB_VNET --query id -o tsv)
SPOKE_VNET_ID=$(az network vnet show -g $RG_NET -n $SPOKE_VNET --query id -o tsv)
az network vnet peering create -g $RG_HUB -n peer-hub-to-$ENV_CODE --vnet-name $HUB_VNET   --remote-vnet $SPOKE_VNET_ID --allow-vnet-access --allow-forwarded-traffic -o none
az network vnet peering create -g $RG_NET -n peer-$ENV_CODE-to-hub --vnet-name $SPOKE_VNET --remote-vnet $HUB_VNET_ID   --allow-vnet-access --allow-forwarded-traffic -o none

# --- Hub firewall (Azure Firewall Basic): spoke egress + DNAT for SSH to the runner
az extension add --name azure-firewall --upgrade -y --only-show-errors
az network public-ip create -g $RG_HUB -n pip-$FW      -l $LOC --sku Standard --allocation-method Static --tags "${TAGS[@]}" -o none
az network public-ip create -g $RG_HUB -n pip-$FW-mgmt -l $LOC --sku Standard --allocation-method Static --tags "${TAGS[@]}" -o none
az network firewall policy create -g $RG_HUB -n afwp-$SIM-hub -l $LOC --sku Basic --tags "${TAGS[@]}" -o none
az network firewall create -g $RG_HUB -n $FW -l $LOC --sku AZFW_VNet --tier Basic --firewall-policy afwp-$SIM-hub \
  --vnet-name $HUB_VNET --conf-name ipconfig --public-ip pip-$FW --m-conf-name mgmt-ipconfig --m-public-ip pip-$FW-mgmt \
  --tags "${TAGS[@]}" -o none
FW_PRIVATE_IP=$(az network firewall show -g $RG_HUB -n $FW --query "ipConfigurations[0].privateIPAddress" -o tsv)
FW_PUBLIC_IP=$(az network public-ip show -g $RG_HUB -n pip-$FW --query ipAddress -o tsv)

az network firewall policy rule-collection-group create -g $RG_HUB --policy-name afwp-$SIM-hub -n rcg-$ENV_CODE --priority 200 -o none
# Sandbox egress: everything from the spoke (production: the APIM / ASE v3 / Foundry / runner allow-lists of platform-team request P5).
az network firewall policy rule-collection-group collection add-filter-collection -g $RG_HUB --policy-name afwp-$SIM-hub \
  --rcg-name rcg-$ENV_CODE -n allow-spoke-egress --collection-priority 300 --action Allow \
  --rule-type NetworkRule --rule-name spoke-any --source-addresses 10.20.0.0/21 --destination-addresses '*' --destination-ports '*' --ip-protocols Any -o none
# SSH to the runner (10.20.0.4) from your IP only: ssh -p 2222 azureuser@$FW_PUBLIC_IP
az network firewall policy rule-collection-group collection add-nat-collection -g $RG_HUB --policy-name afwp-$SIM-hub \
  --rcg-name rcg-$ENV_CODE -n dnat-runner-ssh --collection-priority 100 --action DNAT \
  --rule-name runner-ssh --source-addresses $MY_IP --dest-addr $FW_PUBLIC_IP --destination-ports 2222 \
  --translated-address 10.20.0.4 --translated-port 22 --ip-protocols TCP -o none

# --- Central Log Analytics workspace (management) -----------------------------
# Keeps public ingestion and query: the usage pipeline's Logic App connector queries it through Resource Manager.
az monitor log-analytics workspace create -g $RG_MGMT -n $LAW -l $LOC --retention-time 30 --tags "${TAGS[@]}" -o none
LAW_ID=$(az monitor log-analytics workspace show -g $RG_MGMT -n $LAW --query id -o tsv)

# --- Hub Azure Monitor Private Link Scope (one per DNS) ------------------------
az monitor private-link-scope create -g $RG_MON -n $AMPLS --tags "${TAGS[@]}" -o none
AMPLS_ID=$(az monitor private-link-scope show -g $RG_MON -n $AMPLS --query id -o tsv)
az monitor private-link-scope scoped-resource create -g $RG_MON --scope-name $AMPLS -n $LAW --linked-resource $LAW_ID -o none
```

**3. Hub private DNS zones and the AMPLS private endpoint** (zones are created in parallel):

```bash
# --- Hub private DNS zones, linked to the hub and the spoke --------------------
# (an ALZ hub links them to its DNS resolver; linking the spoke directly gives the same resolution here).
ZONES=(
  privatelink.vaultcore.azure.net privatelink.documents.azure.com privatelink.servicebus.windows.net
  privatelink.cognitiveservices.azure.com privatelink.openai.azure.com privatelink.services.ai.azure.com
  privatelink.blob.core.windows.net privatelink.file.core.windows.net privatelink.table.core.windows.net
  privatelink.queue.core.windows.net privatelink.azure-api.net privatelink.redis.azure.net
  privatelink.azurewebsites.net
  privatelink.monitor.azure.com privatelink.oms.opinsights.azure.com privatelink.ods.opinsights.azure.com
  privatelink.agentsvc.azure-automation.net
)
# APIM classic internal: one zone per default hostname (never an apex azure-api.net zone). The A records
# (-> APIM private IP) are added once stacks/platform has created APIM (Deployment Instructions, step 4).
for h in "" .portal .developer .management .scm; do ZONES+=("$APIM_NAME$h.azure-api.net"); done

HUB_VNET_ID=$(az network vnet show -g $RG_HUB -n $HUB_VNET --query id -o tsv)
SPOKE_VNET_ID=$(az network vnet show -g $RG_NET -n $SPOKE_VNET --query id -o tsv)
for z in "${ZONES[@]}"; do
  ( az network private-dns zone create -g $RG_DNS -n $z --tags "${TAGS[@]}" -o none &&
    az network private-dns link vnet create -g $RG_DNS -z $z -n link-hub       -v $HUB_VNET_ID   -e false -o none &&
    az network private-dns link vnet create -g $RG_DNS -z $z -n link-$ENV_CODE -v $SPOKE_VNET_ID -e false -o none ) &
done
wait
az network private-dns zone list -g $RG_DNS --query "length(@)"   # 22

# --- AMPLS private endpoint in the hub (with its five Azure Monitor zones) ----
AMPLS_ID=$(az monitor private-link-scope show -g $RG_MON -n $AMPLS --query id -o tsv)
az network private-endpoint create -g $RG_MON -n pe-$AMPLS -l $LOC \
  --subnet $(az network vnet subnet show -g $RG_HUB --vnet-name $HUB_VNET -n snet-hub-pe --query id -o tsv) \
  --private-connection-resource-id $AMPLS_ID --group-id azuremonitor --connection-name psc-$AMPLS --tags "${TAGS[@]}" -o none
az network private-endpoint dns-zone-group create -g $RG_MON --endpoint-name pe-$AMPLS -n default \
  --zone-name monitor --private-dns-zone $(az network private-dns zone show -g $RG_DNS -n privatelink.monitor.azure.com --query id -o tsv) -o none
for z in privatelink.oms.opinsights.azure.com privatelink.ods.opinsights.azure.com privatelink.agentsvc.azure-automation.net privatelink.blob.core.windows.net; do
  az network private-endpoint dns-zone-group add -g $RG_MON --endpoint-name pe-$AMPLS -n default \
    --zone-name ${z//./-} --private-dns-zone $(az network private-dns zone show -g $RG_DNS -n $z --query id -o tsv) -o none
done
```

**4. Vended identities, runner subnet and private runner VM:**

```bash
# --- Vended pipeline identities (bootstrap.tfvars existing_pipeline_identities) ---
az identity create -g $RG_ID -n id-tf-$WORKLOAD-$ENV_CODE-plan  -l $LOC --tags "${TAGS[@]}" -o none
az identity create -g $RG_ID -n id-tf-$WORKLOAD-$ENV_CODE-apply -l $LOC --tags "${TAGS[@]}" -o none

# --- Runner subnet in the spoke: UDR 0.0.0.0/0 -> hub firewall, NSG allowing SSH from the firewall DNAT
FW_PRIVATE_IP=$(az network firewall show -g $RG_HUB -n $FW --query "ipConfigurations[0].privateIPAddress" -o tsv)
az network route-table create -g $RG_NET -n rt-$SIM-$ENV_CODE-runner -l $LOC --disable-bgp-route-propagation true --tags "${TAGS[@]}" -o none
az network route-table route create -g $RG_NET --route-table-name rt-$SIM-$ENV_CODE-runner -n default-to-hub-fw \
  --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FW_PRIVATE_IP -o none
az network nsg create -g $RG_NET -n nsg-snet-runner -l $LOC --tags "${TAGS[@]}" -o none
az network nsg rule create -g $RG_NET --nsg-name nsg-snet-runner -n AllowSshViaFirewall --priority 100 --direction Inbound \
  --access Allow --protocol Tcp --source-address-prefixes 10.0.0.0/26 $MY_IP --destination-port-ranges 22 -o none
az network vnet subnet create -g $RG_NET --vnet-name $SPOKE_VNET -n snet-runner --address-prefixes 10.20.0.0/26 \
  --route-table rt-$SIM-$ENV_CODE-runner --network-security-group nsg-snet-runner --default-outbound-access false -o none

# --- Private runner VM (no public IP): Terraform, Task, Azure CLI, Python ------
TF_VERSION=$(cat .terraform-version)   # run from the repository root
cat > /tmp/runner-cloud-init.yaml <<EOF
#cloud-config
package_update: true
packages: [git, jq, unzip, zip, rsync, python3, python3-pip, ca-certificates, curl]
runcmd:
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  - curl -fsSLo /tmp/tf.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip && unzip -o /tmp/tf.zip -d /usr/local/bin
  - sh -c "\$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
EOF
[ -f ~/.ssh/$SIM-$ENV_CODE-runner ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/$SIM-$ENV_CODE-runner -q
az vm create -g $RG_RUNNER -n vm-$SIM-$ENV_CODE-runner -l $LOC --image Ubuntu2404 --size Standard_D2ls_v5 \
  --subnet $(az network vnet subnet show -g $RG_NET --vnet-name $SPOKE_VNET -n snet-runner --query id -o tsv) \
  --private-ip-address 10.20.0.4 --public-ip-address "" --nsg "" --os-disk-size-gb 64 \
  --admin-username azureuser --ssh-key-values ~/.ssh/$SIM-$ENV_CODE-runner.pub \
  --assign-identity $(az identity show -g $RG_ID -n id-tf-$WORKLOAD-$ENV_CODE-apply --query id -o tsv) \
  --custom-data /tmp/runner-cloud-init.yaml --tags "${TAGS[@]}" -o none
```

Write down the values the environment needs:

```bash
echo "hub_firewall_ip = $(az network firewall show -g $RG_HUB -n $FW --query 'ipConfigurations[0].privateIPAddress' -o tsv)"
echo "firewall public IP (runner SSH) = $(az network public-ip show -g $RG_HUB -n pip-$FW --query ipAddress -o tsv)"
echo "apply_principal_id = $(az identity show -g $RG_ID -n id-tf-$WORKLOAD-$ENV_CODE-apply --query principalId -o tsv)"
echo "plan_principal_id  = $(az identity show -g $RG_ID -n id-tf-$WORKLOAD-$ENV_CODE-plan --query principalId -o tsv)"
echo "tenant_id          = $(az account show --query tenantId -o tsv)"
```

The DNAT rule admits SSH only from `MY_IP`. If your IP changes, replace the rule:

```bash
az network firewall policy rule-collection-group collection remove -g $RG_HUB --policy-name afwp-$SIM-hub --rcg-name rcg-$ENV_CODE -n dnat-runner-ssh -o none
# then re-run the add-nat-collection command of step 2 with the new MY_IP
```

## Deployment Instructions

### 1. Create the environment
Copy this folder to `environments/<env>/` (git-ignored; the folder name is the `ENV=` of every task, and
can differ from `environment`, e.g. `environments/alzcorp-01` with `environment = "alzcorp01"`):

```bash
mkdir -p environments/<env> && cp -R examples/alz-corp/*.tfvars examples/alz-corp/access-contracts environments/<env>/
```

Replace every `<...>` placeholder ([table above](#platform-landing-zone-inputs)) and `environment` in
`common.tfvars`. With the simulated platform, also apply the four simulation settings listed above. Then
create the gateway's Entra app (Graph stays off the pipeline) and paste the printed `entra_auth` block
into `gateway-config.tfvars`:

```bash
task entra-setup ENV=<env> -- --no-client   # app-<workload>-<environment>-<seed>-gateway; prints entra_auth = { ... }
task preflight ENV=<env>                     # Azure Policy check (Reader); exemption command if a Deny policy applies
```

Check the inputs before any apply (the full `task plan` needs the state account and the private runner):
`stacks/network` and `stacks/app-hosting` must plan without errors; `stacks/platform` reports only the ASE
lookup until `stacks/app-hosting` has been applied.

### 2. Copy the repository to the private runner
The state account, Key Vault and Logic App storage are private, so every `task` runs on the runner:

```bash
FW_PUBLIC_IP=$(az network public-ip show -g $RG_HUB -n pip-$FW --query ipAddress -o tsv)
rsync -az -e "ssh -p 2222 -i ~/.ssh/$SIM-$ENV_CODE-runner" \
  --exclude .terraform/ --exclude tfplan --exclude '*.tfstate*' --exclude backend_override.tf \
  ./ azureuser@$FW_PUBLIC_IP:~/terraform-ai-hub-gateway-landing-zone/
ssh -p 2222 -i ~/.ssh/$SIM-$ENV_CODE-runner azureuser@$FW_PUBLIC_IP
```

Re-run the `rsync` after every local change to `environments/<env>/` (or keep the folder on the runner only).

### 3. Deploy (on the runner)

```bash
cd ~/terraform-ai-hub-gateway-landing-zone
az login --use-device-code --tenant <tenant-id> && az account set --subscription <workload-subscription-id>

task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account (private endpoint), role assignments; writes backend.hcl
task up ENV=<env>          # preflight, every stack that has a <stack>.tfvars here, then every access contract
```

`task up` runs `network` → `app-hosting` → `platform` → `gateway-config` → `llm-backend-onboarding` →
access contracts. Premium APIM with VNet injection and the ASE v3 each take 1-2 hours on first creation.
A stack runs only if its `<stack>.tfvars` exists, so the files in this folder define the topology. To go
one stack at a time: `task apply STACK=<stack> ENV=<env>`; one contract: `task contract ENV=<env> USE_CASE=team-a-chatbot`.

### 4. Publish the APIM private DNS records (hub)
APIM classic internal listens only on its private IP. Once `stacks/platform` is applied, add the records
to the hub's per-hostname zones (platform team in a real ALZ; with the simulation, on the runner after
re-running the variables block of the simulation):

```bash
APIM_IP=$(az apim show -g $RG_WL -n $APIM_NAME --query "privateIpAddresses[0]" -o tsv)
for h in "" .portal .developer .management .scm; do
  az network private-dns record-set a add-record -g $RG_DNS -z $APIM_NAME$h.azure-api.net -n @ -a $APIM_IP -o none
done
```

### 5. Validate (on the runner)

```bash
task validate ENV=<env>                       # smoke tests against the live gateway
task entra-setup ENV=<env>                    # optional: JWT test client, secret in Key Vault
task jwt-test ENV=<env>                       # optional: JWT tests on products with jwt_required = true
```

See [`DEPLOYMENT_SCENARIOS.md`](../../docs/DEPLOYMENT_SCENARIOS.md) and
[`DEPLOYMENT_GUIDE.md`](../../docs/DEPLOYMENT_GUIDE.md).

## Clean up

```bash
task down ENV=<env>                       # on the runner: contracts and stacks, reverse order
task destroy STACK=bootstrap ENV=<env>    # on the runner: state account and role assignments (last)
az ad app delete --id <gateway-app-client-id>
# Simulated platform (and the vended workload resource group):
for rg in $RG_WL $RG_RUNNER $RG_ID $RG_NET $RG_MON $RG_DNS $RG_MGMT $RG_HUB; do az group delete -n $rg --yes --no-wait; done
```

Key Vault and Foundry (Cognitive Services) accounts are soft-deleted: purge them
(`az keyvault list-deleted`, `az cognitiveservices account list-deleted`) before reusing the names.
