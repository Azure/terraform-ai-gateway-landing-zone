#!/usr/bin/env python3
"""JWT authentication and app-role authorization tests against a deployed gateway: the test cases of the
upstream accelerator's validation/citadel-jwt-authentication-tests.ipynb as a script.

    python3 scripts/jwt_auth_tests.py <env> [--model NAME] [--product ID]    (or: task jwt-test ENV=<env>)

Every access-contract product whose policy sets jwtRequired is tested on each LLM API it grants (Azure
OpenAI API, Universal LLM API, Unified AI API):

  products without requiredRoles                 products with requiredRoles
  T1 api-key + JWT            -> 200             T5 api-key + JWT, token has a required role  -> 200
  T2 api-key only             -> 401             T6 api-key + JWT, token has none of them     -> 403
  T3 api-key + invalid JWT    -> 401             T7 api-key only                               -> 401
  T4 JWT only (no api-key)    -> 401             (T3 and T4 run on these products too)

T5 or T6 runs depending on the roles the test client's token carries. Products that validate tokens of
another identity provider (jwtAudience / jwtIssuer overrides) get only the negative tests.

Inputs: environments/<env>/common.tfvars (names), the APIM JWT-* named values (gateway-config entra_auth),
and the test client of scripts/entra_id_setup.py: ENTRA-TEST-CLIENT-ID / ENTRA-TEST-CLIENT-SECRET from the
platform Key Vault, or the JWT_TEST_CLIENT_ID / JWT_TEST_CLIENT_SECRET environment variables. Subscription
keys are read through the management plane (listSecrets) and never printed. Needs: the APIM service's
gateway reachable from here, Reader + API Management Service Contributor (listSecrets) on it, and Key Vault
Secrets User on the vault. Exit code 1 = at least one test failed.
"""
import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import gateway_env
from gateway_env import Az, AzError

APIM_API_VERSION = "2024-05-01"
AOAI_API_VERSION = "2024-10-21"
INVALID_TOKEN = "INVALID-TEST-TOKEN-FOR-VALIDATION"


def policy_settings(xml):
    """The security-handler inputs a product policy sets (set-variable name="..." value="...")."""
    values = dict(re.findall(r'<set-variable\s+name="([A-Za-z]+)"\s+value="([^"]*)"\s*/>', xml or ""))
    split = lambda v: [x.strip() for x in v.split(",") if x.strip()]  # noqa: E731
    return {
        "jwt_required": values.get("jwtRequired", "").lower() == "true",
        "required_roles": split(values.get("requiredRoles", "")),
        "audience": values.get("jwtAudience", ""),
        "issuer": values.get("jwtIssuer", ""),
        "openid_config_url": values.get("jwtOpenIdConfigUrl", ""),
        "allowed_models": split(values.get("allowedModels", "")),
    }


def policy_text(response):
    """A product policy GET answered as raw XML or as JSON ({properties: {value: <xml>}}); "" for none."""
    if not response:
        return ""
    if response.lstrip().startswith("<"):
        return response
    try:
        return (json.loads(response).get("properties") or {}).get("value", "")
    except ValueError:
        return ""


def token_claims(token):
    """Payload of a JWT (no signature check: only to read aud / iss / roles for the report)."""
    try:
        payload = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (IndexError, ValueError):
        return {}


def uses_gateway_idp(settings, gateway):
    """True when the product validates tokens of the gateway's identity provider (the named values)."""
    return all(settings[k] in ("", gateway[k]) for k in ("audience", "issuer", "openid_config_url"))


def plan_cases(settings, token_roles, own_idp):
    """[(case id, description, headers kind, expected status)] for one product."""
    cases = []
    if own_idp:
        roles = settings["required_roles"]
        if not roles:
            cases.append(("T1", "api-key + JWT", "key+jwt", 200))
        elif set(r.lower() for r in roles) & set(r.lower() for r in token_roles):
            cases.append(("T5", f"api-key + JWT with a required role ({','.join(roles)})", "key+jwt", 200))
        else:
            cases.append(("T6", f"api-key + JWT without the required role ({','.join(roles)})", "key+jwt", 403))
    cases.append(("T7" if settings["required_roles"] else "T2", "api-key only", "key", 401))
    cases.append(("T3", "api-key + invalid JWT", "key+invalid", 401))
    cases.append(("T4", "JWT only (no api-key)", "jwt", 401))
    return cases


def request_for(api_name, api_path, gateway_url, model):
    """(url, body) of a chat completion on an LLM API, or None for an API this script doesn't call."""
    messages = [{"role": "user", "content": "Reply with one word: pong"}]
    path = api_path.strip("/")
    if api_name == "azure-openai-api" or (api_name == "universal-llm-api" and path.endswith("openai")):
        return (f"{gateway_url}/{path}/deployments/{urllib.parse.quote(model, safe='')}/chat/completions"
                f"?api-version={AOAI_API_VERSION}", {"messages": messages})
    if api_name == "universal-llm-api":
        return f"{gateway_url}/{path}/chat/completions", {"model": model, "messages": messages}
    if api_name == "unified-ai-api":
        return f"{gateway_url}/{path}/v1/chat/completions", {"model": model, "messages": messages}
    return None


def call(url, body, headers, attempts=3):
    """POST; (status, error code from the JSON body or "")."""
    data = json.dumps(body).encode()
    for i in range(attempts):
        req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/json", **headers})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.status, ""
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            try:
                err = json.loads(text).get("error", {})
                code = err.get("code", "") if isinstance(err, dict) else ""
            except (ValueError, AttributeError):
                code = ""
            if e.code in (429, 502, 503, 504) and i < attempts - 1:
                time.sleep(5 * (i + 1))
                continue
            return e.code, code
        except (urllib.error.URLError, TimeoutError) as e:
            if i < attempts - 1:
                time.sleep(5 * (i + 1))
                continue
            return 0, str(getattr(e, "reason", e))
    return 0, "no response"


def client_token(tenant_id, client_id, client_secret, scope):
    data = urllib.parse.urlencode({"grant_type": "client_credentials", "client_id": client_id,
                                   "client_secret": client_secret, "scope": scope}).encode()
    req = urllib.request.Request(f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token", data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)["access_token"]
    except urllib.error.HTTPError as e:
        detail = json.loads(e.read().decode(errors="replace") or "{}").get("error_description", "").splitlines()
        raise SystemExit(f"[FAIL] token request failed ({e.code}): {detail[0] if detail else e.reason}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("env")
    ap.add_argument("--model", help="model for the positive tests when a product has no allowedModels")
    ap.add_argument("--product", action="append", help="test only this product ID (repeatable)")
    ap.add_argument("--key-vault", help="vault with the test client's secrets (default: the platform Key Vault)")
    args = ap.parse_args()

    env = gateway_env.Env(args.env)
    az = Az(env.subscription_id)
    rg, apim = env.names["resource_group"], env.names["apim"]
    svc = f"/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}"
    tenant_id = az.run("account", "show")["tenantId"]
    gateway_url = az.rest("GET", az.arm(f"{svc}?api-version={APIM_API_VERSION}"))["properties"]["gatewayUrl"]

    nv = {n: az.rest("GET", az.arm(f"{svc}/namedValues/{n}?api-version={APIM_API_VERSION}"))["properties"].get("value", "")
          for n in ("JWT-AppRegistrationId", "JWT-Issuer", "JWT-OpenIdConfigUrl")}
    gateway = {"audience": nv["JWT-AppRegistrationId"], "issuer": nv["JWT-Issuer"], "openid_config_url": nv["JWT-OpenIdConfigUrl"]}
    print(f"[INFO] Gateway {gateway_url}")
    print(f"[INFO] JWT named values: audience {gateway['audience']}, issuer {gateway['issuer']}")
    if "not-configured" in gateway.values():
        print("[FAIL] the gateway's JWT named values are not configured: set entra_auth = { enabled = true } in"
              " gateway-config.tfvars and apply stacks/gateway-config (scripts/entra_id_setup.py prints the values)")
        return 1

    client_id, client_secret = os.environ.get("JWT_TEST_CLIENT_ID"), os.environ.get("JWT_TEST_CLIENT_SECRET")
    if not (client_id and client_secret):
        vault = args.key_vault or env.names["key_vault"]
        try:
            client_id = az.run("keyvault", "secret", "show", "--vault-name", vault, "--name", "ENTRA-TEST-CLIENT-ID")["value"]
            client_secret = az.run("keyvault", "secret", "show", "--vault-name", vault, "--name", "ENTRA-TEST-CLIENT-SECRET")["value"]
        except AzError as e:
            print(f"[FAIL] test client credentials not found in Key Vault {vault} ({e}); run scripts/entra_id_setup.py"
                  " or set JWT_TEST_CLIENT_ID / JWT_TEST_CLIENT_SECRET")
            return 1
    token = client_token(tenant_id, client_id, client_secret, f"api://{gateway['audience']}/.default")
    claims = token_claims(token)
    token_roles = claims.get("roles", [])
    print(f"[INFO] Test client token: aud {claims.get('aud')}, iss {claims.get('iss')}, roles {', '.join(token_roles) or 'none'}")
    if claims.get("aud") != gateway["audience"] or claims.get("iss") != gateway["issuer"]:
        print("[WARN] the token's aud / iss differ from the JWT named values: the positive tests will fail (v1 vs v2 tokens?)")

    products = az.rest("GET", az.arm(f"{svc}/products?api-version={APIM_API_VERSION}"))["value"]
    subscriptions = az.rest("GET", az.arm(f"{svc}/subscriptions?api-version={APIM_API_VERSION}"))["value"]
    results, tested = [], 0
    for p in products:
        pid = p["name"]
        if args.product and pid not in args.product:
            continue
        pol = az.rest("GET", az.arm(f"{svc}/products/{pid}/policies/policy?api-version={APIM_API_VERSION}"), check=False, raw=True)
        settings = policy_settings(policy_text(pol))
        if not settings["jwt_required"]:
            continue
        sub = next((s for s in subscriptions if s["properties"].get("scope", "").lower().endswith(f"/products/{pid.lower()}")
                    and s["properties"].get("state") == "active"), None)
        if not sub:
            print(f"[WARN] {pid}: requires a JWT but has no active subscription; skipped")
            continue
        key = az.rest("POST", az.arm(f"{svc}/subscriptions/{sub['name']}/listSecrets?api-version={APIM_API_VERSION}"))["primaryKey"]
        own_idp = uses_gateway_idp(settings, gateway)
        model = settings["allowed_models"][0] if settings["allowed_models"] else args.model
        apis = az.rest("GET", az.arm(f"{svc}/products/{pid}/apis?api-version={APIM_API_VERSION}"))["value"]
        roles = ",".join(settings["required_roles"]) or "-"
        print(f"\n[INFO] Product {pid}: required roles {roles}; "
              f"{'gateway identity provider' if own_idp else 'another identity provider (negative tests only)'}; model {model}")
        tested += 1
        for api in apis:
            plan = request_for(api["name"], api["properties"].get("path", ""), gateway_url, model or "")
            if not plan:
                print(f"       {api['name']}: not an LLM API; skipped")
                continue
            url, body = plan
            for case, desc, kind, expected in plan_cases(settings, token_roles, own_idp):
                if expected == 200 and not model:
                    results.append((pid, api["name"], case, desc, expected, None, "no model (pass --model)"))
                    continue
                headers = {}
                if "key" in kind:
                    headers["api-key"] = key
                if kind.endswith("jwt"):
                    headers["Authorization"] = f"Bearer {token}"
                if kind.endswith("invalid"):
                    headers["Authorization"] = f"Bearer {INVALID_TOKEN}"
                status, code = call(url, body, headers)
                results.append((pid, api["name"], case, desc, expected, status, code))
                mark = "PASS" if status == expected else "FAIL"
                print(f"       [{mark}] {case} {api['name']}: {desc} -> {status}{f' ({code})' if code else ''}, expected {expected}")

    if not tested:
        print("[FAIL] no product requires a JWT: set jwt_required = true on a service of an access contract")
        return 1
    failed = [r for r in results if r[5] != r[4]]
    print(f"\n[{'FAIL' if failed else 'OK'}] {len(results) - len(failed)}/{len(results)} JWT tests passed on {tested} product(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AzError as e:
        print(f"[FAIL] {e}")
        sys.exit(1)
