#!/usr/bin/env python3
"""Entra ID setup for JWT authentication on the gateway (the counterpart of the upstream accelerator's
bicep/infra/entra-id-setup/setup.ps1), for teams whose pipeline identity has no Microsoft Graph rights.

    python3 scripts/entra_id_setup.py <env> [options]         (or: task entra-setup ENV=<env> -- [options])

Idempotent; run it as a person who can register applications (az login). It:
  1. finds the gateway app registration by its naming-contract name (app-<workload>-<env>-<seed>-gateway,
     the one stacks/identity creates) or, when it doesn't exist, creates it exactly like stacks/identity:
     scope access_as_user, app roles Task.ReadWrite / Models.Read / MCP.Read / Agent.Read, v2 access
     tokens, identifier URI api://<client-id>, and its service principal. An existing app is not changed.
  2. creates a test client app (<gateway app>-test-client) and its service principal: the identity a
     client application uses to get gateway tokens (OAuth 2.0 client credentials);
  3. gives it a new client secret (older secrets of this script are removed) and stores the client ID
     and secret in Key Vault as ENTRA-TEST-CLIENT-ID / ENTRA-TEST-CLIENT-SECRET;
  4. assigns it exactly the gateway app roles of --client-roles (default Models.Read) and removes the
     others, so the roles claim of its tokens is predictable (scripts/jwt_auth_tests.py relies on it);
  5. prints the gateway-config.tfvars `entra_auth` block. Unlike setup.ps1 it doesn't write the APIM JWT-*
     named values: stacks/gateway-config owns them (task apply STACK=gateway-config sets them).

Options:
  --client-roles R1,R2   gateway app roles of the test client (default Models.Read; "" = none)
  --no-client            only the gateway app (steps 1 and 5)
  --key-vault NAME       vault for the test client's secret (default: the platform Key Vault of the
                         naming contract); "none" = print the secret once instead
  --secret-days N        client secret lifetime in days (default 90; ALZ Enforce-GR-KeyVault allows 90)
  --app-name NAME        gateway app display name (default: the naming contract's gateway_app)
  --remove-client        delete the test client app and its Key Vault secrets, then exit

Permissions: the signed-in user can register applications (or holds Application Developer); Key Vault
Secrets Officer on the vault. Assigning app roles to the test client's service principal needs ownership of
the gateway app's service principal (stacks/identity and this script make their creator an owner) or an
Entra admin role (Cloud Application Administrator, Application Administrator, Privileged Role Administrator).
Without either the script does everything else and prints the command for an admin.
"""
import argparse
import datetime
import os
import sys
import tempfile

import gateway_env
from gateway_env import GRAPH, Az, AzError

# Canonical IDs of modules/gateway-entra-app (stable across re-runs and tools).
SCOPE_ID = "00000000-0000-0000-0000-000000000001"
APP_ROLES = [
    ("00000000-0000-0000-0000-000000000002", "ReadWrite", "Task.ReadWrite", "Full read and write access to all gateway capabilities"),
    ("00000000-0000-0000-0000-000000000003", "Models.Read", "Models.Read", "Access to LLM model endpoints (chat completions, embeddings)"),
    ("00000000-0000-0000-0000-000000000004", "MCP.Read", "MCP.Read", "Access to MCP tool endpoints"),
    ("00000000-0000-0000-0000-000000000005", "Agent.Read", "Agent.Read", "Access to agent endpoints"),
]
MS_GRAPH_APP_ID = "00000003-0000-0000-c000-000000000000"
USER_READ_SCOPE = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
SECRET_NAME = "entra-id-setup"
KV_CLIENT_ID = "ENTRA-TEST-CLIENT-ID"
KV_CLIENT_SECRET = "ENTRA-TEST-CLIENT-SECRET"


def gateway_app_body(display_name):
    """The app registration of modules/gateway-entra-app, as a Microsoft Graph application object."""
    return {
        "displayName": display_name,
        "signInAudience": "AzureADMyOrg",
        "isFallbackPublicClient": True,
        "api": {
            "requestedAccessTokenVersion": 2,
            "oauth2PermissionScopes": [{
                "id": SCOPE_ID,
                "isEnabled": True,
                "type": "User",
                "value": "access_as_user",
                "adminConsentDisplayName": "Access AI Hub Gateway API",
                "adminConsentDescription": "Allow access to AI Hub Gateway API",
                "userConsentDisplayName": "Access AI Hub Gateway API",
                "userConsentDescription": "Allow access to AI Hub Gateway API",
            }],
        },
        "appRoles": [
            {"id": rid, "allowedMemberTypes": ["User", "Application"], "displayName": name,
             "description": desc, "isEnabled": True, "value": value}
            for rid, name, value, desc in APP_ROLES
        ],
        "requiredResourceAccess": [{
            "resourceAppId": MS_GRAPH_APP_ID,
            "resourceAccess": [{"id": USER_READ_SCOPE, "type": "Scope"}],
        }],
    }


def role_changes(app_roles, assigned_role_ids, wanted_values):
    """(role ids to add, role ids to remove) so the client holds exactly the wanted role values."""
    by_value = {r["value"]: r["id"] for r in app_roles if r.get("isEnabled", True)}
    unknown = [v for v in wanted_values if v not in by_value]
    if unknown:
        raise ValueError(f"unknown app role(s) {', '.join(unknown)}; the gateway app defines {', '.join(sorted(by_value))}")
    wanted = {by_value[v] for v in wanted_values}
    assigned = set(assigned_role_ids)
    return sorted(wanted - assigned), sorted(assigned & set(by_value.values()) - wanted)


def find_app(az, display_name):
    apps = az.rest("GET", f"{GRAPH}/applications?$filter=displayName eq '{display_name}'&$select=id,appId,displayName,appRoles,identifierUris,api")
    found = (apps or {}).get("value", [])
    if len(found) > 1:
        raise SystemExit(f"[FAIL] {len(found)} app registrations are named '{display_name}': remove the duplicates or pass --app-name")
    return found[0] if found else None


def ensure_sp(az, app_id):
    sps = az.rest("GET", f"{GRAPH}/servicePrincipals?$filter=appId eq '{app_id}'&$select=id,appId")
    if sps and sps.get("value"):
        return sps["value"][0]["id"], False
    return az.rest("POST", f"{GRAPH}/servicePrincipals", {"appId": app_id})["id"], True


def kv_set(az, vault, name, value, expires):
    fd, path = tempfile.mkstemp()
    try:
        with os.fdopen(fd, "w") as f:
            f.write(value)
        az.run("keyvault", "secret", "set", "--vault-name", vault, "--name", name, "--file", path,
               "--encoding", "utf-8", "--expires", expires, "--content-type", "entra-test-client")
    finally:
        os.unlink(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("env")
    ap.add_argument("--client-roles", default="Models.Read")
    ap.add_argument("--no-client", action="store_true")
    ap.add_argument("--key-vault")
    ap.add_argument("--secret-days", type=int, default=90)
    ap.add_argument("--app-name")
    ap.add_argument("--remove-client", action="store_true")
    args = ap.parse_args()

    env = gateway_env.Env(args.env)
    az = Az(env.subscription_id)
    account = az.run("account", "show")
    tenant_id = account["tenantId"]
    app_name = args.app_name or env.names["gateway_app"]
    client_name = f"{app_name}-test-client"
    vault = None if (args.key_vault or "").lower() == "none" else (args.key_vault or env.names["key_vault"])
    print(f"[INFO] Environment {args.env}: tenant {tenant_id}, signed in as {account['user']['name']}")
    print(f"[INFO] Gateway app '{app_name}', test client '{client_name}', Key Vault {vault or '(none)'}")

    if args.remove_client:
        client = find_app(az, client_name)
        if client:
            az.rest("DELETE", f"{GRAPH}/applications/{client['id']}")
            print(f"[OK]   deleted app registration {client_name} ({client['appId']})")
        else:
            print(f"[OK]   {client_name} doesn't exist")
        if vault:
            for name in (KV_CLIENT_ID, KV_CLIENT_SECRET):
                if az.run("keyvault", "secret", "delete", "--vault-name", vault, "--name", name, check=False) is not None:
                    print(f"[OK]   deleted Key Vault secret {name} (soft-deleted)")
        return 0

    # 1. Gateway app
    print("[1/5] Gateway app registration")
    app = find_app(az, app_name)
    if app:
        print(f"[OK]   found {app_name} ({app['appId']}); left unchanged")
    else:
        app = az.rest("POST", f"{GRAPH}/applications", gateway_app_body(app_name))
        print(f"[OK]   created {app_name} ({app['appId']})")
    if f"api://{app['appId']}" not in (app.get("identifierUris") or []):
        az.rest("PATCH", f"{GRAPH}/applications/{app['id']}", {"identifierUris": [f"api://{app['appId']}"]})
        print(f"[OK]   identifier URI api://{app['appId']}")
    gw_sp, created = ensure_sp(az, app["appId"])
    print(f"[OK]   service principal {gw_sp}{' (created)' if created else ''}")
    roles = [r for r in (app.get("appRoles") or []) if r.get("isEnabled", True)]
    if (app.get("api") or {}).get("requestedAccessTokenVersion") != 2:
        print("[WARN] the app issues v1 access tokens: the JWT-Issuer named value (…/v2.0) won't match them")

    if not args.no_client:
        wanted = [r.strip() for r in args.client_roles.split(",") if r.strip()]
        try:
            role_changes(roles, [], wanted)
        except ValueError as e:
            print(f"[FAIL] --client-roles: {e}")
            return 1

        # 2. Test client app
        print("[2/5] Test client app registration")
        client = find_app(az, client_name)
        if not client:
            client = az.rest("POST", f"{GRAPH}/applications", {"displayName": client_name, "signInAudience": "AzureADMyOrg"})
            print(f"[OK]   created {client_name} ({client['appId']})")
        else:
            print(f"[OK]   found {client_name} ({client['appId']})")
        client_sp, created = ensure_sp(az, client["appId"])
        print(f"[OK]   service principal {client_sp}{' (created)' if created else ''}")

        # 3. Client secret
        print("[3/5] Client secret")
        end = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=args.secret_days)
        secret = az.rest("POST", f"{GRAPH}/applications/{client['id']}/addPassword", {
            "passwordCredential": {"displayName": SECRET_NAME, "endDateTime": end.strftime("%Y-%m-%dT%H:%M:%SZ")},
        })
        creds = az.rest("GET", f"{GRAPH}/applications/{client['id']}?$select=passwordCredentials")["passwordCredentials"]
        for c in creds:
            if c.get("displayName") == SECRET_NAME and c["keyId"] != secret["keyId"]:
                az.rest("POST", f"{GRAPH}/applications/{client['id']}/removePassword", {"keyId": c["keyId"]})
        print(f"[OK]   new secret valid until {end:%Y-%m-%d} (older '{SECRET_NAME}' secrets removed)")
        if vault:
            try:
                expires = end.strftime("%Y-%m-%dT%H:%M:%SZ")
                kv_set(az, vault, KV_CLIENT_ID, client["appId"], expires)
                kv_set(az, vault, KV_CLIENT_SECRET, secret["secretText"], expires)
                print(f"[OK]   stored in Key Vault {vault} as {KV_CLIENT_ID} / {KV_CLIENT_SECRET}")
            except AzError as e:
                print(f"[FAIL] couldn't write to Key Vault {vault} ({e}).")
                print("       Needs Key Vault Secrets Officer and network access (dev_access, or a runner in the VNet);"
                      " or re-run with --key-vault none to print the secret instead.")
                return 1
        else:
            print(f"[OK]   client ID {client['appId']}; secret (shown once): {secret['secretText']}")

        # 4. App role assignments
        print("[4/5] App role assignments")
        assigned = az.rest("GET", f"{GRAPH}/servicePrincipals/{client_sp}/appRoleAssignments")["value"]
        mine = {a["appRoleId"]: a["id"] for a in assigned if a["resourceId"] == gw_sp}
        add, remove = role_changes(roles, list(mine), wanted)
        by_id = {r["id"]: r["value"] for r in roles}
        try:
            for role_id in add:
                az.rest("POST", f"{GRAPH}/servicePrincipals/{gw_sp}/appRoleAssignedTo",
                        {"principalId": client_sp, "resourceId": gw_sp, "appRoleId": role_id})
            for role_id in remove:
                az.rest("DELETE", f"{GRAPH}/servicePrincipals/{gw_sp}/appRoleAssignedTo/{mine[role_id]}")
            print(f"[OK]   {client_name} holds {', '.join(wanted) or 'no roles'}"
                  f" ({len(add)} added, {len(remove)} removed; new tokens carry them)")
        except AzError as e:
            if "Authorization_RequestDenied" not in str(e):
                raise
            # Granting an app role to a service principal needs ownership of the gateway app's service
            # principal or Cloud Application Administrator / Application Administrator / Privileged Role
            # Administrator.
            print("[WARN] not allowed to assign app roles: you neither own the gateway app's service principal"
                  " nor hold Cloud Application Administrator, Application Administrator or Privileged Role Administrator.")
            print("       The test client works without roles: contracts with required_roles answer it 403.")
            for role_id in add:
                print(f"       Ask an Entra admin to grant {by_id[role_id]}:")
                print(f"         az rest --method POST --url {GRAPH}/servicePrincipals/{gw_sp}/appRoleAssignedTo \\")
                print(f"           --body '{{\"principalId\":\"{client_sp}\",\"resourceId\":\"{gw_sp}\",\"appRoleId\":\"{role_id}\"}}'")
            for role_id in remove:
                print(f"       and to remove {by_id[role_id]}:")
                print(f"         az rest --method DELETE --url {GRAPH}/servicePrincipals/{gw_sp}/appRoleAssignedTo/{mine[role_id]}")

    # 5. What to configure
    print("[5/5] gateway-config")
    print("       The JWT-* named values come from gateway-config.tfvars. With Graph Application.Read.All")
    print("       on the pipeline the app is found by name:")
    print("         entra_auth = { enabled = true }")
    print("       otherwise set it explicitly:")
    print(f'         entra_auth = {{ enabled = true, tenant_id = "{tenant_id}", client_id = "{app["appId"]}", audience = "api://{app["appId"]}" }}')
    print(f"       then: task apply STACK=gateway-config ENV={args.env}; contracts opt in with jwt_required = true.")
    if not args.no_client:
        print(f"       Token for the test client: POST https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token")
        print(f"         grant_type=client_credentials, client_id=<{KV_CLIENT_ID}>, client_secret=<{KV_CLIENT_SECRET}>,"
              f" scope=api://{app['appId']}/.default")
        print(f"       Test it: task jwt-test ENV={args.env}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AzError as e:
        print(f"[FAIL] {e}")
        sys.exit(1)
