"""Helpers of citadel-acceptance-tests.ipynb: a result registry (one entry per test case), gateway
discovery (APIM, products, subscriptions, policies), authenticated calls, Log Analytics queries,
resource inspection and direct network probes.

Azure access goes through the az CLI (az login), like scripts/gateway_env.py, which this module reuses
together with scripts/jwt_auth_tests.py. Secrets (subscription keys, client secrets, tokens) are kept in
memory only: they are never printed, logged or written to the results file. Evidence that needs to show
"which key" uses fingerprint() (the first 8 hex digits of a SHA-256).
"""
from __future__ import annotations

import csv
import datetime
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parents[2]
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import gateway_env  # noqa: E402
import jwt_auth_tests as jt  # noqa: E402
from gateway_env import Az, AzError  # noqa: E402,F401

APIM_API = "2024-05-01"
APIM_DEBUG_API = "2023-05-01-preview"
APIM_MCP_API = "2025-03-01-preview"  # MCP APIs are listed (and readable) from this version on

PASS, FAIL, NOT_CONFIGURED, SKIPPED, MANUAL, ERROR, NOT_RUN = (
    "PASS", "FAIL", "NOT CONFIGURED", "SKIPPED", "MANUAL", "ERROR", "NOT RUN")
ICONS = {PASS: "✅", FAIL: "❌", NOT_CONFIGURED: "🚫", SKIPPED: "⏭️", MANUAL: "📝", ERROR: "💥", NOT_RUN: "·"}

# The customer's test catalogue: id, category, title, priority, status in the customer's sheet.
CASES = [
    ("AUTH-001", "Authentication", "Create APIM Product via Terraform (access contract)", "P1", "Yes"),
    ("AUTH-002", "Authentication", "Subscription created and key stored in Key Vault", "P1", "Yes"),
    ("AUTH-003", "Authentication", "Valid subscription key + Entra JWT returns a completion", "P1", "Yes"),
    ("AUTH-004", "Authentication", "Missing JWT rejected with 401 before the backend", "P1", "Yes"),
    ("AUTH-005", "Authentication", "Missing or invalid subscription key with a valid JWT rejected", "P1", "Yes"),
    ("AUTH-007", "Authentication", "JWT with the wrong audience or issuer rejected by validate-jwt", "P1", "Yes"),
    ("AUTH-009", "Authentication", "Subscription key rotation without downtime", "P2", ""),
    ("AUTH-012", "Authentication", "Managed identity authentication from an Azure-hosted consumer", "P2", "Yes"),
    ("AUTHZ-003", "Authorization", "Product scoped to approved models only", "P1", "Yes"),
    ("MCP-AUTH-002", "MCP", "MCP with OAuth authorization code + PKCE (user-delegated)", "P2", ""),
    ("MCP-AUTH-003", "MCP", "MCP with OAuth client credentials", "P2", ""),
    ("MCP-AUTH-004", "MCP", "MCP call without a bearer token rejected with 401", "P2", ""),
    ("MCP-BACKEND-004", "MCP", "MCP backend private only; direct public call fails", "P2", ""),
    ("POL-002", "Policy", "PII masked or blocked and not written to logs", "P1", "Yes"),
    ("POL-003", "Policy", "Jailbreak / prompt injection blocked (Prompt Shields)", "P1", "No"),
    ("POL-004", "Policy", "Harmful content blocked in the response (outbound content safety)", "P1", "No"),
    ("POL-005", "Policy", "Rate limit returns 429 with Retry-After", "P1", "Yes"),
    ("POL-006", "Policy", "Token quota enforced and reset at period rollover", "P1", "Yes"),
    ("POL-007", "Policy", "Semantic cache hit", "P2", "Yes"),
    ("POL-008", "Policy", "Semantic cache miss falls through to the backend", "P2", "Yes"),
    ("POL-009", "Policy", "Policy fragment change promoted DEV -> PRE-PROD with overrides", "P2", "Yes"),
    ("CB-001", "Circuit breaker", "Circuit breaker trips on repeated backend failures", "P2", ""),
    ("CB-002", "Circuit breaker", "Circuit breaker event raises an alert routed to on-call", "P2", ""),
    ("PBI-001", "Usage & reporting", "Usage event flows end to end with correlation ID, tokens and product", "P1", "Yes"),
    ("PBI-002", "Usage & reporting", "Power BI reflects request volume within the refresh window", "P2", "Yes"),
    ("PBI-003", "Usage & reporting", "Chargeback by product / line of business", "P1", "Yes"),
    ("PBI-005", "Usage & reporting", "PTU utilisation accuracy", "P2", ""),
    ("PBI-007", "Usage & reporting", "Mandatory tags on all resources", "P3", ""),
    ("PBI-010", "Usage & reporting", "FinOps / SRE drill-down by tag, product, subscription, app", "P2", ""),
    ("TOK-001", "Token accounting", "Recorded token counts match the provider's", "P3", ""),
    ("TOK-002", "Token accounting", "Token quota boundary is precise", "P1", "Yes"),
    ("PROV-001", "Provisioning", "End-to-end automated provisioning (ITSM -> pipeline -> Key Vault)", "P3", ""),
    ("SEC-001", "Security", "No public network access on platform components", "P1", "Yes"),
    ("SEC-002", "Security", "Backends not reachable bypassing the gateway", "P1", "Yes"),
    ("SEC-003", "Security", "Secrets never appear in logs", "P2", "Yes"),
]
CASE_INDEX = {c[0]: c for c in CASES}


def fingerprint(secret):
    """Short, non-reversible identifier of a secret for evidence (never the secret itself)."""
    return hashlib.sha256((secret or "").encode()).hexdigest()[:8] if secret else "-"


def unquote(value):
    """python-hcl2 >= 5 keeps the quotes of string literals: strip them recursively."""
    if isinstance(value, str):
        return value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value
    if isinstance(value, list):
        return [unquote(v) for v in value]
    if isinstance(value, dict):
        return {unquote(k): unquote(v) for k, v in value.items()}
    return value


def print_table(rows, columns=None, max_width=60):
    """Plain-text table of a list of dicts (works in every notebook front end and in exports)."""
    if not rows:
        print("   (no rows)")
        return
    columns = columns or list(rows[0].keys())
    cell = lambda v: " ".join(str(v).split())[:max_width] if v is not None else ""  # noqa: E731
    widths = {c: max(len(c), *(len(cell(r.get(c))) for r in rows)) for c in columns}
    print("   " + "  ".join(c.ljust(widths[c]) for c in columns))
    print("   " + "  ".join("-" * widths[c] for c in columns))
    for r in rows:
        print("   " + "  ".join(cell(r.get(c)).ljust(widths[c]) for c in columns))


# ---------------------------------------------------------------------------------------------
# Result registry
# ---------------------------------------------------------------------------------------------

class Stop(Exception):
    """Ends a test case early with an explicit status (skip, not configured, manual, fail)."""

    def __init__(self, status, message):
        super().__init__(message)
        self.status, self.message = status, message


class Case:
    """One test case run: `with results.case("AUTH-003") as t:` ... t.check(condition, "what")."""

    def __init__(self, results, case_id):
        if case_id not in CASE_INDEX:
            raise KeyError(f"unknown test case {case_id}")
        self.results, self.id = results, case_id
        self.checks, self.notes, self.evidence = [], [], {}
        self.started = None

    def __enter__(self):
        _, category, title, priority, _sheet = CASE_INDEX[self.id]
        self.started = time.time()
        print(f"━━ {self.id} · {title} ({category}, {priority})")
        return self

    def info(self, message):
        self.notes.append(message)
        print(f"   · {message}")

    def check(self, ok, message):
        ok = bool(ok)
        self.checks.append((ok, message))
        print(f"   {'✔' if ok else '✘'} {message}")
        return ok

    def record(self, key, value):
        """Evidence kept in the results (must never be a secret)."""
        self.evidence[key] = value

    def fail(self, message):
        self.check(False, message)
        raise Stop(FAIL, message)

    def skip(self, message):
        raise Stop(SKIPPED, message)

    def manual(self, message):
        raise Stop(MANUAL, message)

    def not_configured(self, message, snippet=None):
        if snippet:
            print("   Policy / configuration needed:")
            print("\n".join("      " + line for line in snippet.strip("\n").splitlines()))
        raise Stop(NOT_CONFIGURED, message)

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None and issubclass(exc_type, KeyboardInterrupt):
            return False
        failed = [m for ok, m in self.checks if not ok]
        if exc_type is Stop:
            status, message = exc.status, exc.message
        elif exc_type is not None:
            status, message = ERROR, f"{exc_type.__name__}: {exc}"
        elif failed:
            status, message = FAIL, "; ".join(failed)
        elif self.checks:
            status, message = PASS, f"{len(self.checks)} check(s) passed"
        else:
            status, message = MANUAL, "no automated check ran"
        duration = round(time.time() - self.started, 1)
        self.results.add(self.id, status, message, self.evidence, duration)
        print(f"   {ICONS[status]} {self.id}: {status} — {message} ({duration}s)\n")
        return True  # a failing case never stops "Run All"


class Results:
    """Results of one notebook run, in catalogue order; exported to CSV for the customer's sheet."""

    def __init__(self, env):
        self.env, self.rows = env, {}
        self.started = datetime.datetime.now(datetime.timezone.utc)

    def case(self, case_id):
        return Case(self, case_id)

    def add(self, case_id, status, message, evidence=None, duration=None):
        self.rows[case_id] = {"status": status, "message": message, "evidence": evidence or {},
                              "duration_s": duration,
                              "at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}

    def table(self):
        out = []
        for cid, category, title, priority, sheet in CASES:
            r = self.rows.get(cid, {"status": NOT_RUN, "message": "", "evidence": {}, "duration_s": None, "at": ""})
            out.append({"id": cid, "category": category, "title": title, "priority": priority, "sheet": sheet,
                        "status": r["status"], "message": r["message"], "duration_s": r["duration_s"], "at": r["at"],
                        "evidence": json.dumps(r["evidence"], default=str, sort_keys=True)})
        return out

    def summary(self):
        rows = self.table()
        counts = {}
        for r in rows:
            counts[r["status"]] = counts.get(r["status"], 0) + 1
        print("   " + "   ".join(f"{ICONS[s]} {s}: {n}" for s, n in sorted(counts.items())))
        print_table([{"": ICONS[r["status"]], **{k: r[k] for k in ("id", "priority", "status", "message")}} for r in rows],
                    max_width=90)
        return counts

    def export_csv(self, directory):
        directory = pathlib.Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{self.env}-{self.started.strftime('%Y%m%dT%H%M%SZ')}.csv"
        rows = self.table()
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        return path


# ---------------------------------------------------------------------------------------------
# Access contracts (environments/<env>/access-contracts/*.tfvars)
# ---------------------------------------------------------------------------------------------

def load_contracts(env, root=ROOT):
    """Every contract of the environment, with the product IDs the access-contract module derives."""
    try:
        import hcl2
    except ImportError as e:
        raise ImportError("python-hcl2 is required to read the contracts: pip install -r validation/requirements.txt") from e
    folder = pathlib.Path(root) / "environments" / env / "access-contracts"
    contracts = []
    for f in sorted(folder.glob("*.tfvars")):
        with f.open(encoding="utf-8") as fh:
            data = unquote(hcl2.load(fh))
        uc = data.get("use_case") or {}
        bu, name, uenv = uc.get("business_unit", ""), uc.get("use_case_name", ""), uc.get("environment", "")
        postfix = f"{bu}-{name}-{uenv}"
        mapping = data.get("api_name_mapping") or {}
        kv = data.get("key_vault") or {}
        services = []
        for s in data.get("services") or []:
            s = dict(s)
            s["product_id"] = f"{s['code']}-{postfix}"
            s["display_name"] = f"{s['code']} {bu} {name} {uenv}"
            s["apis"] = mapping.get(s["code"], [])
            s["key_secret"] = s["api_key_secret_name"].replace("_", "-").lower()
            s["endpoint_secret"] = s["endpoint_secret_name"].replace("_", "-").lower()
            services.append(s)
        contracts.append({"file": f.name, "use_case": uc, "postfix": postfix, "services": services,
                          "key_vault": {"enabled": kv.get("enabled", True), "id": kv.get("id")}})
    return contracts


# ---------------------------------------------------------------------------------------------
# Product policy inspection
# ---------------------------------------------------------------------------------------------

def attributes(tag_text):
    return dict(re.findall(r'([\w-]+)="([^"]*)"', tag_text or ""))


def token_limit(xml):
    """Attributes of the llm-token-limit policy of a product policy ({} when none)."""
    m = re.search(r"<llm-token-limit\b([^>]*)>", xml or "")
    return attributes(m.group(1)) if m else {}


def features(xml):
    """Optional AI policies present in a policy document."""
    xml = xml or ""
    cs = re.search(r"<llm-content-safety\b([^>]*)>", xml)
    cs_attrs = attributes(cs.group(1)) if cs else {}
    variables = dict(re.findall(r'<set-variable\s+name="([A-Za-z]+)"\s+value="([^"@]*)"', xml))
    return {
        "pii": variables.get("piiAnonymizationEnabled", "").lower() == "true" and "pii-anonymization" in xml,
        "pii_blocking": variables.get("piiBlockingEnabled", "").lower() == "true",
        "content_safety": bool(cs),
        "shield_prompt": cs_attrs.get("shield-prompt", "").lower() == "true",
        "content_safety_completions": cs_attrs.get("enforce-on-completions", "").lower() == "true",
        # A custom lookup policy, or the access contract opt-in (services[*].semantic_cache) that turns on
        # the semantic-cache-lookup fragment of the LLM APIs.
        "semantic_cache": bool(re.search(r"<(llm|azure-openai)-semantic-cache-lookup\b", xml))
        or variables.get("semanticCacheEnabled", "").lower() == "true",
        "jwt_validation": bool(re.search(r"<validate-(jwt|azure-ad-token)\b|fragment-id=\"security-handler\"", xml)),
    }


def models_from_fragment(xml):
    """Model names of the get-available-models fragment (llm-routing writes one comment per model)."""
    return sorted(set(re.findall(r"// Model: (\S+) from backend:", xml or "")))


SNIPPETS = {
    "jwt": """
# access contract (.tfvars), per service:
jwt_required   = true
required_roles = []   # or app roles, e.g. ["Models.Read"]
""",
    "pii": """
<!-- access contract service: policy_xml = <custom product policy> (keep the generated rules) -->
<inbound>
    <base />
    <set-variable name="piiAnonymizationEnabled" value="true" />
    <!-- or block instead of masking: <set-variable name="piiBlockingEnabled" value="true" /> -->
    <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
    <include-fragment fragment-id="pii-anonymization" />
    <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
</inbound>
<outbound>
    <base />
    <set-variable name="piiDeanonymizeContentInput" value="@(context.Response.Body.As<string>(preserveContent: true))" />
    <include-fragment fragment-id="pii-deanonymization" />
    <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
</outbound>
<!-- needs gateway-config features.pii_anonymization = true (deploys the fragments).
     The LLM logs (largeLanguageModel messages = all) still record the prompt as received:
     set messages = "none" for products that carry PII. -->
""",
    "content_safety": """
<!-- access contract service: policy_xml, inbound (403 when a check fails) -->
<llm-content-safety backend-id="content-safety-backend" shield-prompt="true" enforce-on-completions="true">
    <categories output-type="EightSeverityLevels">
        <category name="Hate" threshold="3" />
        <category name="Violence" threshold="3" />
        <category name="SelfHarm" threshold="3" />
        <category name="Sexual" threshold="3" />
    </categories>
</llm-content-safety>
<!-- optional alert: <set-variable name="alertOnContentSafety" value="true" /> (raise-alert-events) -->
""",
    "semantic_cache": """
# platform.tfvars: Redis as the APIM external cache, and an embeddings deployment
features = { semantic_cache = true }
foundry  = { models = [ ..., { name = "text-embedding-3-small", version = "1", capacity = 50 } ] }

# gateway-config.tfvars: embeddings backend + the semantic-cache-lookup / -store fragments
semantic_cache = { enabled = true }

# access contract (.tfvars), per service: opt in
semantic_cache = true
# see docs/DEPLOYMENT_GUIDE.md 6.9
""",
    "mcp_auth": """
<!-- policy of the MCP API (gateway-config apis: policy_xml), inbound -->
<validate-jwt header-name="Authorization" require-scheme="Bearer" failed-validation-httpcode="401"
              failed-validation-error-message="Unauthorized">
    <openid-config url="{{JWT-OpenIdConfigUrl}}" />
    <audiences><audience>{{JWT-AppRegistrationId}}</audience></audiences>
    <issuers><issuer>{{JWT-Issuer}}</issuer></issuers>
</validate-jwt>
<!-- and return the protected resource metadata (RFC 9728) on 401 for OAuth-capable MCP clients -->
""",
    "rate_limit": """
# access contract (.tfvars), per service:
token_limit = { tokens_per_minute = 300 }                                  # LLM APIs: 429 + Retry-After
tool_limit  = { calls_per_minute = 30 }                                    # tool (MCP) APIs: requests per minute
""",
    "quota": """
# access contract (.tfvars), per service:
token_limit = { token_quota = 2000, token_quota_period = "Hourly" }        # 403 when exhausted
""",
    "circuit_breaker_backend": """
# llm-backend-onboarding.tfvars: a failing test backend (httpbin answers 404 for the appended path,
# counted as a failure by the rule below), then add its model to a validation product.
llm_backends = [{
  backend_id       = "cb-test-backend"
  backend_type     = "external"
  endpoint         = "https://httpbin.org/status/503"
  supported_models = [{ name = "cb-test-model" }]
  circuit_breaker  = { failure_count = 3, failure_interval = "PT1M", trip_duration = "PT1M",
                       status_code_ranges = [{ min = 400, max = 599 }] }
}]
""",
    "alert_rule": """
# Metric alert on the gateway's "AI Gateway Alert" custom metric (namespace ai-gateway-alerts), e.g. with az:
az monitor metrics alert create -g <rg> -n aigw-backend-failure --scopes <app-insights-id> \\
  --condition "total 'ai-gateway-alerts/AI Gateway Alert' > 0 where alertType includes backend-failure" \\
  --window-size 5m --evaluation-frequency 1m --action <on-call-action-group-id>
""",
}


# ---------------------------------------------------------------------------------------------
# HTTP calls
# ---------------------------------------------------------------------------------------------

@dataclass
class Call:
    status: int
    latency_ms: int
    headers: dict = field(default_factory=dict)
    body: object = None
    text: str = ""
    error: str = ""

    @property
    def code(self):
        """error.code of an APIM / backend error body ("" when none)."""
        err = self.body.get("error") if isinstance(self.body, dict) else None
        return (err.get("code") or "") if isinstance(err, dict) else ""

    @property
    def message(self):
        """message of an APIM error body ({"statusCode", "message"}) or error.message ("" when none)."""
        if not isinstance(self.body, dict):
            return ""
        err = self.body.get("error")
        return (err.get("message") or "") if isinstance(err, dict) else (self.body.get("message") or "")

    @property
    def usage(self):
        if not isinstance(self.body, dict):
            return {}
        return self.body.get("usage") or {}

    @property
    def content(self):
        try:
            return self.body["choices"][0]["message"]["content"] or ""
        except (TypeError, KeyError, IndexError):
            return ""

    @property
    def request_id(self):
        return self.headers.get("UAIG-Request-Id", "")

    def describe(self):
        extra = f" {self.code}" if self.code else (f" {self.error}" if self.error else "")
        return f"HTTP {self.status}{extra} in {self.latency_ms} ms"


def http(method, url, headers=None, body=None, timeout=120):
    import requests
    started = time.time()
    try:
        r = requests.request(method, url, headers=headers or {}, json=body, timeout=timeout)
    except requests.RequestException as e:
        return Call(0, int((time.time() - started) * 1000), error=type(e).__name__)
    try:
        parsed = r.json()
    except ValueError:
        parsed = None
    return Call(r.status_code, int((time.time() - started) * 1000), dict(r.headers), parsed, r.text[:2000])


def is_private(host):
    try:
        return all(ipaddress.ip_address(info[4][0]).is_private for info in socket.getaddrinfo(host, 443))
    except (socket.gaierror, ValueError):
        return None


BLOCK_MARKERS = ("public network access is disabled", "publicnetworkaccess", "forbiddenbyfirewall",
                 "forbiddenbyconnection", "blocked by your cosmos db account firewall", "not from a trusted service",
                 "public access is disabled", "ip has been blocked", "denied by the ip", "is not allowed",
                 "authorizationfailure", "virtual network")


def probe(url, token=None, timeout=10):
    """Direct call from this machine: (verdict, detail). verdict is blocked (no DNS / route, or a firewall
    answer) or reachable (the service answered). Azure AI services, Key Vault and Event Hubs answer 401
    before they evaluate their network rules, so the call carries an Entra token for the service: then a
    closed network answers 403 "public access is disabled" and an open one answers the request."""
    import requests
    host = urllib.parse.urlparse(url).hostname or url
    try:
        addresses = sorted({i[4][0] for i in socket.getaddrinfo(host, 443)})
    except socket.gaierror:
        return "blocked", "DNS does not resolve from this network"
    private = all(ipaddress.ip_address(a).is_private for a in addresses)
    headers = {"Authorization": f"Bearer {token}", "x-ms-version": "2023-11-03"} if token else {}
    try:
        r = requests.get(url if "://" in url else f"https://{url}/", headers=headers, timeout=timeout)
    except requests.RequestException as e:
        return "blocked", f"{type(e).__name__} ({'private IP ' if private else ''}{', '.join(addresses[:2])})"
    text = r.text[:3000].lower()
    if r.status_code == 403 and any(m in text for m in BLOCK_MARKERS):
        return "blocked", f"HTTP 403 firewall / private access only ({', '.join(addresses[:2])})"
    return "reachable", f"HTTP {r.status_code} from {', '.join(addresses[:2])}{' (private IP)' if private else ''}"


# Host suffix -> (token audience, data-plane path that needs the network check) for the direct probes.
PROBE_PLANS = [
    ((".cognitiveservices.azure.com", ".openai.azure.com", ".services.ai.azure.com"),
     "https://cognitiveservices.azure.com", "openai/models?api-version=2024-10-21"),
    ((".vault.azure.net",), "https://vault.azure.net", "secrets?api-version=7.4"),
    ((".servicebus.windows.net",), "https://eventhubs.azure.net", "$Resources/eventhubs?api-version=2017-04"),
    ((".blob.core.windows.net",), "https://storage.azure.com", "?comp=list"),
    ((".search.windows.net",), "https://search.azure.com", "indexes?api-version=2024-07-01"),
]


def probe_plan(url):
    """(probe URL, token audience or None) for a service endpoint."""
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname or ""
    for suffixes, audience, path in PROBE_PLANS:
        if host.endswith(suffixes):
            return f"https://{host}/{path}", audience
    return f"https://{host}/", None


# ---------------------------------------------------------------------------------------------
# Gateway
# ---------------------------------------------------------------------------------------------

LLM_API_ORDER = ("azure-openai-api", "universal-llm-api", "unified-ai-api")


class Gateway:
    """A deployed environment (environments/<env>), seen through the management plane and the gateway."""

    def __init__(self, env, default_model=None, key_vault=None):
        self.env = gateway_env.Env(env)
        self.az = Az(self.env.subscription_id)
        self.names = self.env.names
        self.rg, self.apim_name = self.names["resource_group"], self.names["apim"]
        self.svc = f"/resourceGroups/{self.rg}/providers/Microsoft.ApiManagement/service/{self.apim_name}"
        self.apim_id = f"/subscriptions/{self.env.subscription_id}{self.svc}"
        self.apim = self.get(self.svc)
        props = self.apim["properties"]
        self.gateway_url = props["gatewayUrl"]
        self.sku = self.apim["sku"]["name"]
        self.vnet_type = props.get("virtualNetworkType", "None")
        account = self.az.run("account", "show")
        self.tenant_id, self.signed_in = account["tenantId"], account["user"]["name"]
        self.default_model = default_model
        self.key_vault = key_vault or self.names["key_vault"]
        self._cache, self._token, self.used = {}, (None, 0), {}

    # -- management plane ---------------------------------------------------------------------
    def url(self, path, api=APIM_API):
        base = f"https://management.azure.com{path}" if path.startswith("/subscriptions/") else self.az.arm(path)
        return f"{base}{'&' if '?' in base else '?'}api-version={api}" if api else base

    def get(self, path, api=APIM_API, check=True, raw=False):
        return self.az.rest("GET", self.url(path, api), check=check, raw=raw)

    def post(self, path, body=None, api=APIM_API, check=True):
        return self.az.rest("POST", self.url(path, api), body=body, check=check)

    def cached(self, key, fn):
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    def named_value(self, name):
        nv = self.get(f"{self.svc}/namedValues/{name}", check=False)
        if not nv:
            return None
        if nv["properties"].get("secret"):
            return "<secret>"
        return nv["properties"].get("value")

    def jwt_config(self):
        return {"audience": self.named_value("JWT-AppRegistrationId") or "",
                "issuer": self.named_value("JWT-Issuer") or "",
                "openid_config_url": self.named_value("JWT-OpenIdConfigUrl") or ""}

    def products(self):
        return self.cached("products", lambda: self.get(f"{self.svc}/products")["value"])

    def product_ids(self):
        return [p["name"] for p in self.products()]

    def policy(self, product_id):
        return self.cached(("policy", product_id), lambda: jt.policy_text(
            self.get(f"{self.svc}/products/{product_id}/policies/policy", check=False, raw=True)))

    def api_policy(self, api_name):
        return self.cached(("api-policy", api_name), lambda: jt.policy_text(
            self.get(f"{self.svc}/apis/{api_name}/policies/policy?format=rawxml", api=APIM_MCP_API, check=False, raw=True)))

    def settings(self, product_id):
        xml = self.policy(product_id)
        s = jt.policy_settings(xml)
        s.update({"token_limit": token_limit(xml), "features": features(xml)})
        return s

    def product_apis(self, product_id):
        return self.cached(("apis", product_id), lambda: [
            {"name": a["name"], "path": a["properties"].get("path", "")}
            for a in self.get(f"{self.svc}/products/{product_id}/apis")["value"]])

    def apis(self):
        return self.cached("apis", lambda: self.get(f"{self.svc}/apis")["value"])

    def subscriptions(self):
        return self.cached("subscriptions", lambda: self.get(f"{self.svc}/subscriptions")["value"])

    def subscription(self, product_id):
        return next((s for s in self.subscriptions()
                     if s["properties"].get("scope", "").lower().endswith(f"/products/{product_id.lower()}")
                     and s["properties"].get("state") == "active"), None)

    def keys(self, product_id, refresh=False):
        """{"primaryKey", "secondaryKey"} of the product's active subscription (memory only)."""
        if refresh:
            self._cache.pop(("keys", product_id), None)
        sub = self.subscription(product_id)
        if not sub:
            raise LookupError(f"{product_id} has no active subscription")
        return self.cached(("keys", product_id),
                           lambda: self.post(f"{self.svc}/subscriptions/{sub['name']}/listSecrets"))

    def regenerate_primary_key(self, product_id):
        sub = self.subscription(product_id)
        self.post(f"{self.svc}/subscriptions/{sub['name']}/regeneratePrimaryKey", check=True)
        return self.keys(product_id, refresh=True)

    def backends(self):
        return self.cached("backends", lambda: self.get(f"{self.svc}/backends")["value"])

    def fragment(self, fragment_id):
        f = self.get(f"{self.svc}/policyFragments/{fragment_id}?format=rawxml", check=False)
        return ((f or {}).get("properties") or {}).get("value", "")

    def fragments(self):
        return self.cached("fragments", lambda: self.get(f"{self.svc}/policyFragments")["value"])

    def available_models(self):
        return self.cached("models", lambda: models_from_fragment(self.fragment("get-available-models")))

    def fallback_model(self):
        """DEFAULT_MODEL, else the first chat-looking model behind the gateway."""
        if self.default_model:
            return self.default_model
        models = self.available_models()
        return next((m for m in models if re.search(r"gpt|phi|llama|mistral|claude|gemini", m, re.I)),
                    models[0] if models else None)

    # -- product selection ----------------------------------------------------------------------
    def find_products(self, predicate):
        """Product IDs whose settings (policy_settings + token_limit + features) satisfy predicate."""
        return [pid for pid in self.product_ids() if self.subscription(pid) and predicate(self.settings(pid))]

    def target(self, product_id, model=None, api=None):
        """{"api", "url", "body", "model"} of a chat completion through the product's first LLM API."""
        settings = self.settings(product_id)
        model = model or (settings["allowed_models"][0] if settings["allowed_models"] else self.fallback_model())
        if not model:
            raise LookupError(f"{product_id}: no model (the product allows every model: set DEFAULT_MODEL)")
        apis = {a["name"]: a for a in self.product_apis(product_id)}
        order = [api] if api else [n for n in LLM_API_ORDER if n in apis]
        for name in order:
            plan = jt.request_for(name, apis[name]["path"], self.gateway_url, model)
            if plan:
                return {"api": name, "url": plan[0], "body": plan[1], "model": model}
        raise LookupError(f"{product_id}: no LLM API in the product ({', '.join(apis) or 'none'})")

    # -- identities and tokens ------------------------------------------------------------------
    def test_client(self):
        cid, secret = os.environ.get("JWT_TEST_CLIENT_ID"), os.environ.get("JWT_TEST_CLIENT_SECRET")
        if cid and secret:
            return cid, secret
        return (self.secret(self.key_vault, "ENTRA-TEST-CLIENT-ID"),
                self.secret(self.key_vault, "ENTRA-TEST-CLIENT-SECRET"))

    def token(self, audience=None):
        """Client-credentials token of the test client for the gateway app (or another audience)."""
        audience = audience or self.jwt_config()["audience"]
        cached, expires = self._token
        if audience == self.jwt_config()["audience"] and cached and time.time() < expires:
            return cached
        cid, secret = self.test_client()
        scope = audience if audience.startswith("https://") else f"api://{audience}/.default"
        if audience.startswith("https://") and not audience.endswith("/.default"):
            scope = f"{audience.rstrip('/')}/.default"
        try:
            tok = jt.client_token(self.tenant_id, cid, secret, scope)
        except SystemExit as e:  # the CLI helper exits on failure; a notebook must keep running
            raise RuntimeError(str(e)) from None
        if audience == self.jwt_config()["audience"]:
            self._token = (tok, time.time() + 45 * 60)
        return tok

    def cli_token(self, resource=None, scope=None, timeout=60):
        """Token of the signed-in az CLI identity (user-delegated, issued to the Azure CLI client). A scope the
        CLI has no consent for can make az wait for an interactive sign-in: the timeout ends it."""
        args = [self.az.exe, "account", "get-access-token", "-o", "json", "--only-show-errors"]
        args += ["--scope", scope] if scope else ["--resource", resource]
        try:
            p = subprocess.run(args, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise AzError(f"az account get-access-token: no token within {timeout}s (consent or interactive sign-in needed)") from None
        if p.returncode != 0:
            raise AzError(f"az account get-access-token: {(p.stderr.strip().splitlines() or ['failed'])[-1]}")
        return json.loads(p.stdout)["accessToken"]

    def probe(self, url):
        """Direct call to a service endpoint with the signed-in identity's token for that service."""
        target, audience = probe_plan(url)
        token = self.cached(("cli-token", audience), lambda: self.cli_token(resource=audience)) if audience else None
        return probe(target, token)

    def secret(self, vault, name):
        return self.az.run("keyvault", "secret", "show", "--vault-name", vault, "--name", name, "--query", "value")

    def auth_headers(self, product_id, key="primaryKey", jwt=True):
        headers = {"api-key": self.keys(product_id)[key]}
        if jwt and self.settings(product_id)["jwt_required"]:
            headers["Authorization"] = f"Bearer {self.token()}"
        return headers

    # -- data plane -----------------------------------------------------------------------------
    def chat(self, product_id, model=None, prompt=None, headers=None, api=None, max_tokens=None, timeout=120):
        """Chat completion through the gateway; headers default to the product's key (+ JWT when required)."""
        t = self.target(product_id, model, api)
        body = dict(t["body"])
        if prompt:
            body["messages"] = [{"role": "user", "content": prompt}]
        if max_tokens:
            body["max_completion_tokens"] = max_tokens
        call = http("POST", t["url"], self.auth_headers(product_id) if headers is None else headers, body, timeout)
        call.api, call.model = t["api"], t["model"]
        self.used.setdefault(product_id, 0)
        self.used[product_id] += 1
        return call

    def run_until(self, product_id, stop_status, max_requests, prompt=None):
        """Sequential chat calls until stop_status (or max_requests); one dict per call with the tokens
        the provider reported and the product's cumulative consumption before the call."""
        attempts, cumulative = [], 0
        for i in range(max_requests):
            c = self.chat(product_id, prompt=prompt)
            tokens = c.usage.get("total_tokens", 0)
            attempts.append({"n": i + 1, "status": c.status, "tokens": tokens, "cumulative_before": cumulative,
                             "retry_after": c.headers.get("Retry-After", ""), "latency_ms": c.latency_ms,
                             "code": c.code or c.message})
            cumulative += tokens
            if c.status == stop_status or c.status not in (200, stop_status):
                break
        return attempts

    def mcp_call(self, api, headers=None, method="initialize"):
        """JSON-RPC call on an MCP server published by APIM. A passthrough server (backendId) answers on
        <gateway>/<path>; a server built from an API's operations (mcpTools) on <gateway>/<path>/mcp."""
        path = api["properties"].get("path", api["name"]).strip("/")
        url = f"{self.gateway_url}/{path}" if api["properties"].get("backendId") else f"{self.gateway_url}/{path}/mcp"
        body = {"jsonrpc": "2.0", "id": 1, "method": method,
                "params": {"protocolVersion": "2025-03-26", "capabilities": {},
                           "clientInfo": {"name": "citadel-acceptance-tests", "version": "1.0"}}}
        h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json", **(headers or {})}
        return http("POST", url, h, body, timeout=60)

    def mcp_apis(self):
        return self.cached("mcp-apis", lambda: [a for a in self.get(f"{self.svc}/apis", api=APIM_MCP_API)["value"]
                                                if a["properties"].get("type") == "mcp"])

    def set_secret(self, vault, name, value, content_type, valid_days=60):
        """Writes a secret through a temporary file (the value never appears on a command line)."""
        import tempfile
        expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=valid_days)).strftime("%Y-%m-%dT%H:%M:%SZ")
        fd, tmp = tempfile.mkstemp()
        try:
            with os.fdopen(fd, "w") as f:
                f.write(value)
            self.az.run("keyvault", "secret", "set", "--vault-name", vault, "--name", name, "--file", tmp,
                        "--encoding", "utf-8", "--content-type", content_type, "--expires", expires, "--query", "id")
        finally:
            os.unlink(tmp)

    def traced_chat(self, product_id, headers, model=None, prompt=None):
        """(call, trace) with an APIM debug trace; trace None when tracing isn't available."""
        t = self.target(product_id, model)
        body = dict(t["body"])
        if prompt:
            body["messages"] = [{"role": "user", "content": prompt}]
        creds = self.az.rest("POST", self.url(f"{self.svc}/gateways/managed/listDebugCredentials", APIM_DEBUG_API),
                             body={"credentialsExpireAfter": "PT1H", "apiId": f"{self.apim_id}/apis/{t['api']}",
                                   "purposes": ["tracing"]}, check=False)
        trace_headers = dict(headers)
        if creds and creds.get("token"):
            trace_headers["Apim-Debug-Authorization"] = creds["token"]
        call = http("POST", t["url"], trace_headers, body)
        trace_id = call.headers.get("Apim-Trace-Id")
        trace = None
        if trace_id:
            trace = self.az.rest("POST", self.url(f"{self.svc}/gateways/managed/listTrace", APIM_DEBUG_API),
                                 body={"traceId": trace_id}, check=False)
        return call, trace

    # -- Azure resources ------------------------------------------------------------------------
    def resources(self):
        return self.cached("resources", lambda: self.az.run("resource", "list", "-g", self.rg))

    def resource_details(self, ids):
        out = []
        for i in range(0, len(ids), 20):
            batch = self.az.run("resource", "show", "--ids", *ids[i:i + 20])
            out.extend(batch if isinstance(batch, list) else [batch])
        return out

    def resource_group(self):
        return self.az.run("group", "show", "-n", self.rg)

    def workspace(self):
        """(resource ID, customer ID) of the Log Analytics workspace APIM sends its logs to."""
        def find():
            ds = self.get(f"{self.svc}/providers/Microsoft.Insights/diagnosticSettings", api="2021-05-01-preview",
                          check=False) or {}
            ws_id = next((d["properties"].get("workspaceId") for d in ds.get("value", [])
                          if d["properties"].get("workspaceId")), None)
            if not ws_id:
                ws_id = next((r["id"] for r in self.resources()
                              if r["type"].lower() == "microsoft.operationalinsights/workspaces"), None)
            if not ws_id:
                raise LookupError("no Log Analytics workspace found for the gateway")
            ws = self.get(ws_id, api="2022-10-01")
            return ws_id, ws["properties"]["customerId"]
        return self.cached("workspace", find)

    def kql(self, query, timespan="PT6H"):
        _, customer_id = self.workspace()
        return self.az.run("monitor", "log-analytics", "query", "--workspace", customer_id,
                           "--analytics-query", query, "--timespan", timespan) or []

    def wait_kql(self, query, timespan="PT6H", timeout=900, interval=30, min_rows=1, label="rows"):
        """Poll a query until it returns min_rows (ingestion into Log Analytics takes minutes)."""
        deadline = time.time() + timeout
        while True:
            rows = self.kql(query, timespan)
            if len(rows) >= min_rows or time.time() > deadline:
                return rows
            print(f"   … waiting for {label} in Log Analytics ({int(deadline - time.time())}s left)")
            time.sleep(interval)

    def role_assignments(self, scope):
        return self.az.run("role", "assignment", "list", "--scope", scope, "--include-inherited") or []

    def logic_app(self):
        return next((r for r in self.resources() if r["type"].lower() == "microsoft.web/sites"
                     and "workflowapp" in (r.get("kind") or "").lower()), None)

    def run_workflow(self, workflow, trigger="Recurrence"):
        app = self.logic_app()
        base = f"{app['id']}/hostruntime/runtime/webhooks/workflow/api/management/workflows/{workflow}"
        self.az.rest("POST", self.url(f"{base}/triggers/{trigger}/run", "2018-11-01"))
        return base

    def workflow_runs(self, workflow, top=5):
        app = self.logic_app()
        base = f"{app['id']}/hostruntime/runtime/webhooks/workflow/api/management/workflows/{workflow}"
        return (self.az.rest("GET", self.url(f"{base}/runs?$top={top}", "2018-11-01"), check=False) or {}).get("value", [])


# ---------------------------------------------------------------------------------------------
# Public network access
# ---------------------------------------------------------------------------------------------

IN_SCOPE_TYPES = {
    "microsoft.apimanagement/service": "API Management",
    "microsoft.keyvault/vaults": "Key Vault",
    "microsoft.documentdb/databaseaccounts": "Cosmos DB",
    "microsoft.eventhub/namespaces": "Event Hubs",
    "microsoft.search/searchservices": "AI Search",
    "microsoft.cognitiveservices/accounts": "AI Services / Language / Content Safety",
    "microsoft.cache/redis": "Azure Cache for Redis",
    "microsoft.cache/redisenterprise": "Azure Managed Redis",
    "microsoft.storage/storageaccounts": "Storage",
    "microsoft.web/sites": "Logic App / App Service",
    "microsoft.operationalinsights/workspaces": "Log Analytics",
    "microsoft.insights/components": "Application Insights",
    "microsoft.containerregistry/registries": "Container Registry",
}


def public_access(resource):
    """(state, detail) for one resource: private | restricted | public | n/a."""
    t = resource["type"].lower()
    p = resource.get("properties") or {}
    if t == "microsoft.apimanagement/service":
        if p.get("virtualNetworkType") == "Internal":
            return "private", "VNet Internal mode (no public gateway endpoint)"
        if p.get("publicNetworkAccess") == "Disabled":
            return "private", "publicNetworkAccess Disabled"
        return "public", f"virtualNetworkType {p.get('virtualNetworkType', 'None')}, publicNetworkAccess {p.get('publicNetworkAccess')}"
    if t in ("microsoft.operationalinsights/workspaces", "microsoft.insights/components"):
        ing, qry = p.get("publicNetworkAccessForIngestion"), p.get("publicNetworkAccessForQuery")
        state = "private" if ing == "Disabled" and qry == "Disabled" else ("restricted" if "Disabled" in (ing, qry) else "public")
        return state, f"ingestion {ing}, query {qry}"
    pna = p.get("publicNetworkAccess")
    acl = p.get("networkAcls") or p.get("networkRuleSet") or p.get("networkRuleSets") or {}
    default_action = acl.get("defaultAction") if isinstance(acl, dict) else None
    if t == "microsoft.web/sites":
        return ("private" if pna == "Disabled" else "public"), f"publicNetworkAccess {pna}"
    if pna is None and t == "microsoft.cache/redisenterprise":
        return "n/a", "set on the database / private endpoint (check the cluster's publicNetworkAccess in the portal)"
    if str(pna).lower() == "disabled":
        return "private", "publicNetworkAccess Disabled"
    if default_action == "Deny":
        rules = len(acl.get("ipRules") or []) + len(acl.get("virtualNetworkRules") or [])
        return "restricted", f"publicNetworkAccess {pna}, firewall default Deny ({rules} rule(s))"
    if pna is None and not acl:
        return "n/a", "no public network access setting"
    return "public", f"publicNetworkAccess {pna}, firewall {default_action or 'none'}"


def endpoints(resource):
    """Data-plane URLs of a resource worth probing directly."""
    p = resource.get("properties") or {}
    t = resource["type"].lower()
    urls = []
    if t == "microsoft.keyvault/vaults":
        urls.append(p.get("vaultUri"))
    elif t == "microsoft.documentdb/databaseaccounts":
        urls.append(p.get("documentEndpoint"))
    elif t == "microsoft.cognitiveservices/accounts":
        # the account's own hosts only (endpoints also lists shared global services: translator, speech)
        own = {(p.get("customSubDomainName") or resource["name"]).lower()}
        urls.append(p.get("endpoint"))
        urls.extend(u for u in (p.get("endpoints") or {}).values()
                    if isinstance(u, str) and (urllib.parse.urlparse(u).hostname or "").split(".")[0].lower() in own)
    elif t == "microsoft.search/searchservices":
        urls.append(f"https://{resource['name']}.search.windows.net/")
    elif t == "microsoft.eventhub/namespaces":
        urls.append(p.get("serviceBusEndpoint"))
    elif t == "microsoft.storage/storageaccounts":
        urls.append((p.get("primaryEndpoints") or {}).get("blob"))
    elif t == "microsoft.web/sites":
        urls.append(f"https://{p.get('defaultHostName')}/" if p.get("defaultHostName") else None)
    elif t == "microsoft.cache/redisenterprise":
        urls.append(f"https://{p.get('hostName')}/" if p.get("hostName") else None)
    return sorted({u for u in urls if isinstance(u, str) and u.startswith("https://")})


AZURE_SUFFIXES = (".azure.com", ".azure.net", ".windows.net", ".azure-api.net", ".azurewebsites.net", ".azurecr.io")


def is_azure_host(url):
    host = urllib.parse.urlparse(url).hostname or ""
    return host.endswith(AZURE_SUFFIXES)


# ---------------------------------------------------------------------------------------------
# Secret scanning
# ---------------------------------------------------------------------------------------------

JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")


def scan_for_secrets(rows, secrets):
    """[(table, column, kind)] where a known secret or a JWT appears in log rows (values never returned)."""
    hits = []
    for row in rows:
        table = row.get("Type") or row.get("$table") or "?"
        for column, value in row.items():
            if not isinstance(value, str) or len(value) < 16:
                continue
            for label, secret in secrets.items():
                if secret and secret in value:
                    hits.append((table, column, label))
            if JWT_RE.search(value):
                hits.append((table, column, "JWT"))
    return sorted(set(hits))


# ---------------------------------------------------------------------------------------------
# Background load (key rotation)
# ---------------------------------------------------------------------------------------------

class Loop(threading.Thread):
    """Calls fn() every interval seconds until stop(); keeps (time, status) of every call."""

    def __init__(self, fn, interval=2.0):
        super().__init__(daemon=True)
        self.fn, self.interval, self.calls = fn, interval, []
        self._stop_event = threading.Event()

    def run(self):
        while not self._stop_event.is_set():
            call = self.fn()
            self.calls.append((time.time(), call.status))
            self._stop_event.wait(self.interval)

    def stop(self):
        self._stop_event.set()
        self.join(timeout=180)
        return self.calls


def run_az_script(az, *args):
    """az call whose output is plain text (vm run-command)."""
    p = subprocess.run([az.exe, *args, "-o", "json", "--only-show-errors"], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL)
    if p.returncode != 0:
        raise AzError(p.stderr.strip().splitlines()[-1] if p.stderr.strip() else f"exit {p.returncode}")
    return json.loads(p.stdout or "null")
