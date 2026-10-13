# Entra ID JWT authentication

The gateway's two-layer authentication, as in the upstream accelerator's
[Entra ID / JWT guide](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/main/guides/entraid-auth-validation.md):
every API requires the **subscription key** (it ties a request to an access
contract), and a contract can additionally require a **JWT**, optionally with an
**app role**. The `security-handler` fragment enforces it uniformly on the Azure
OpenAI, Universal LLM and Unified AI APIs.

Base topology: [quickstart](../quickstart/) (public StandardV2, laptop runs), plus:

| File | What it adds |
|---|---|
| `identity.tfvars` | `stacks/identity`: the gateway app registration (audience of the tokens; app roles `Task.ReadWrite`, `Models.Read`, `MCP.Read`, `Agent.Read`; v2 tokens; no secret) |
| `gateway-config.tfvars` | `entra_auth = { enabled = true }`: the `JWT-OpenIdConfigUrl`, `JWT-Issuer` and `JWT-AppRegistrationId` named values from that app |
| `llm-backend-onboarding.tfvars` | the Unified AI API, so all three LLM APIs are covered |
| `access-contracts/team-a-jwt.tfvars` | key + JWT (`jwt_required = true`) on the three APIs |
| `access-contracts/team-b-roles.tfvars` | key + JWT + app role: `MODELS` needs `Models.Read`, `FULL` needs `Task.ReadWrite` (`required_roles`) |
| `access-contracts/partner-tenant.tfvars` | key + a token of **another** tenant or provider (`jwt_audience`, `jwt_issuer`, `jwt_openid_config_url`); replace the `<partner-...>` placeholders or delete the file |

## Deploy

Copy this folder to `environments/<env>/`, replace the `<...>` placeholders
(and `environment` in `common.tfvars`), then:

```bash
task bootstrap ENV=<env>   # once (Contributor + User Access Administrator): state account, workload RG, pipeline identities; writes backend.hcl
task up ENV=<env>          # every stack that has a <stack>.tfvars here (identity first), then every access contract
```

`stacks/identity` needs Microsoft Graph rights to register an application:
run it as a person who can (as `task up` does from a laptop), or with bootstrap
`graph_permissions = true`. A pipeline without Graph rights can use
`scripts/entra_id_setup.py` instead: it creates the same app and prints the
explicit `entra_auth` values for `gateway-config.tfvars` (remove
`identity.tfvars` then).

## A client identity and the tests

```bash
task entra-setup ENV=<env>   # test client app + secret (Key Vault: ENTRA-TEST-CLIENT-ID / -SECRET) + app role Models.Read
task jwt-test ENV=<env>      # upstream's 7 test cases on every product that requires a JWT
```

`entra_id_setup.py` finds the gateway app by name (it doesn't change an
existing one), creates `<gateway app>-test-client` with a 90-day secret in the
platform Key Vault, and assigns it exactly the roles of `--client-roles`
(default `Models.Read`). Assigning a role needs ownership of the gateway app's
service principal (whoever applied `stacks/identity` or ran the script owns it)
or an Entra admin role; otherwise the script prints the command for an admin.
`jwt_auth_tests.py` reads every product policy that
sets `jwtRequired`, gets a token for the test client (client credentials,
`scope = api://<gateway app client ID>/.default`) and calls each LLM API of the
product:

| Product | Case | Expected |
|---|---|---|
| `LLM-TeamA-SecureChat-DEV` | T1 key + JWT | 200 |
| every JWT product | T2 / T7 key only | 401 `jwt_required` |
| every JWT product | T3 key + invalid JWT | 401 |
| every JWT product | T4 JWT only | 401 |
| `MODELS-TeamB-RoleAuth-DEV` | T5 key + JWT with `Models.Read` | 200 |
| `FULL-TeamB-RoleAuth-DEV` | T6 key + JWT without `Task.ReadWrite` | 403 `insufficient_role` |
| `LLM-Partner-External-DEV` | T2–T4 only (the test client can't get a partner token) | 401 |

A client application does the same: get a token for
`api://<gateway app client ID>/.default` and send it with the key:

```bash
TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id="$CLIENT_ID" -d client_secret="$CLIENT_SECRET" \
  -d scope="api://<gateway-app-client-id>/.default" | jq -r .access_token)
curl -s "$ENDPOINT/chat/completions" -H "api-key: $KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello"}]}'
```

A managed identity (an app in Azure) requests the same scope and needs no
secret; give it app roles like the test client. Remove the test client with
`task entra-setup ENV=<env> -- --remove-client`. Details:
[Deployment Guide, Entra ID JWT authentication](../../docs/DEPLOYMENT_GUIDE.md#66-entra-id-jwt-authentication).

A stack runs only if its `<stack>.tfvars` exists, so the files in this
folder define the topology. See `docs/deployment-scenarios.md`.
