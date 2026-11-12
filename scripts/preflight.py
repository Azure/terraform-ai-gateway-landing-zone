#!/usr/bin/env python3
"""Pre-deploy Azure Policy check: finds Deny policies this repository is known to
trip over BEFORE the first apply, instead of at the end of a long deployment.

    python3 scripts/preflight.py <env> [--no-fail]      (or: task preflight ENV=<env>)

Reads environments/<env>/common.tfvars (subscription, workload, environment), lists
the policy assignments that apply to the workload resource group (or the
subscription while the group doesn't exist yet), resolves initiatives and their
effects, and reports every known check that is denied and not exempted.
Needs only Reader on the scope. Exit code 1 = at least one blocking finding
(--no-fail: report only). If Azure Policy can't be queried the check is skipped
with a warning (it is advisory, never a reason to stop).

To cover another policy, add an entry to CHECKS (see docs/operations/platform-team-requests.md).
"""
import argparse
import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys

CHECKS = [
    {
        "id": "c15dcc82-b93c-4dcb-9332-fbf121685b54",
        "name": "API Management calls to API backends should be authenticated",
        "affects": "every APIM backend (stacks/gateway-config, stacks/llm-backend-onboarding)",
        "why": (
            "The definition denies a backend that has a URL but no credentials.certificate and no "
            "credentials.authorization.scheme. The backends here authenticate with the APIM managed "
            "identity (credentials.managedIdentity / authentication-managed-identity in policy), which the "
            "definition doesn't recognise: a false positive."
        ),
        "request": "P6 in docs/operations/platform-team-requests.md",
    },
]


def guid_of(resource_id):
    return resource_id.rstrip("/").split("/")[-1].lower()


def read_tfvar(text, key):
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    return m.group(1) if m else None


def resolve_param(value, assignment_params, set_params):
    """Resolves "[parameters('x')]" from the assignment, then the initiative default."""
    if not isinstance(value, str):
        return value
    m = re.fullmatch(r"\[parameters\('([^']+)'\)\]", value.strip())
    if not m:
        return value
    name = m.group(1)
    if name in (assignment_params or {}):
        return assignment_params[name].get("value")
    return (set_params or {}).get(name, {}).get("defaultValue")


def effect_of(ref, assignment_params, set_params, definition):
    """Effect of one definition reference inside an initiative (or of a direct assignment)."""
    effect = (ref.get("parameters") or {}).get("effect", {}).get("value")
    if effect is not None:
        effect = resolve_param(effect, assignment_params, set_params)
    if effect is None and definition:
        params = definition.get("parameters") or {}
        effect = params.get("effect", {}).get("defaultValue")
        if effect is None:
            effect = ((definition.get("policyRule") or {}).get("then") or {}).get("effect")
        effect = resolve_param(effect, assignment_params, set_params)
    return str(effect).lower() if effect is not None else "unknown"


def override_effect(overrides, ref_id):
    """Effect set by an assignment override (kind policyEffect) that selects this reference."""
    for o in overrides or []:
        if o.get("kind") != "policyEffect":
            continue
        selectors = [x for x in o.get("selectors") or [] if x.get("kind") == "policyDefinitionReferenceId"]
        if not selectors or any(
            (ref_id in (x.get("in") or [])) if x.get("in") else (ref_id not in (x.get("notIn") or []))
            for x in selectors
        ):
            return str(o.get("value")).lower()
    return None


def in_not_scopes(scope, not_scopes):
    s = scope.lower().rstrip("/")
    return any(s == n.lower().rstrip("/") or s.startswith(n.lower().rstrip("/") + "/") for n in not_scopes or [])


def exempted(assignment_id, ref_id, exemptions, now):
    for e in exemptions:
        if (e.get("policyAssignmentId") or "").lower() != assignment_id.lower():
            continue
        expires = e.get("expiresOn")
        if expires and datetime.datetime.fromisoformat(expires.replace("Z", "+00:00")) <= now:
            continue
        refs = e.get("policyDefinitionReferenceIds") or []
        if not refs or (ref_id and ref_id in refs):
            return e
    return None


def find_hits(assignments, scope, load_set, load_definition):
    """[(check, assignment, reference id, effect)] for every known check an assignment carries."""
    by_id = {c["id"]: c for c in CHECKS}
    hits = []
    for a in assignments:
        props = a.get("properties", a)
        if in_not_scopes(scope, props.get("notScopes")):
            continue
        def_id = props.get("policyDefinitionId", "")
        a_params = props.get("parameters") or {}
        if "/policysetdefinitions/" in def_id.lower():
            pset = load_set(def_id) or {}
            set_params = pset.get("parameters") or {}
            for ref in pset.get("policyDefinitions") or []:
                check = by_id.get(guid_of(ref.get("policyDefinitionId", "")))
                if check:
                    definition = None
                    if (ref.get("parameters") or {}).get("effect") is None:
                        definition = load_definition(ref["policyDefinitionId"])
                    ref_id = ref.get("policyDefinitionReferenceId")
                    effect = override_effect(props.get("overrides"), ref_id) or effect_of(ref, a_params, set_params, definition)
                    hits.append((check, a, ref_id, effect))
        elif guid_of(def_id) in by_id:
            definition = load_definition(def_id)
            effect = override_effect(props.get("overrides"), None) or effect_of(
                {"parameters": {"effect": a_params.get("effect", {})}}, a_params, {}, definition)
            hits.append((by_id[guid_of(def_id)], a, None, effect))
    return hits


class Az:
    def __init__(self):
        self.exe = shutil.which("az")
        self.error = None

    def run(self, *args):
        if not self.exe:
            self.error = "az CLI not found"
            return None
        p = subprocess.run([self.exe, *args, "-o", "json", "--only-show-errors"],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if p.returncode != 0:
            self.error = p.stderr.strip().splitlines()[-1] if p.stderr.strip() else f"exit {p.returncode}"
            return None
        return json.loads(p.stdout or "null")

    def scope_args(self, resource_id):
        m = re.search(r"/managementGroups/([^/]+)/", resource_id, re.IGNORECASE)
        if m:
            return ["--management-group", m.group(1)]
        m = re.search(r"/subscriptions/([^/]+)/", resource_id, re.IGNORECASE)
        return ["--subscription", m.group(1)] if m else []

    def load_set(self, set_id):
        return self.run("policy", "set-definition", "show", "--name", guid_of(set_id), *self.scope_args(set_id))

    def load_definition(self, def_id):
        return self.run("policy", "definition", "show", "--name", guid_of(def_id), *self.scope_args(def_id))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("env")
    ap.add_argument("--no-fail", action="store_true", help="report only; always exit 0")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    tfvars = root / "environments" / args.env / "common.tfvars"
    if not tfvars.exists():
        print(f"[WARN] {tfvars} not found; nothing to check")
        return 0
    text = tfvars.read_text()
    sub = read_tfvar(text, "subscription_id")
    workload, environment = read_tfvar(text, "workload"), read_tfvar(text, "environment")
    rg = read_tfvar(text, "resource_group") or (f"rg-{workload}-{environment}" if workload and environment else None)
    if not sub:
        print("[WARN] subscription_id not found in common.tfvars; skipping the policy preflight")
        return 0

    az = Az()
    scope = f"/subscriptions/{sub}"
    if rg and az.run("group", "show", "--subscription", sub, "-n", rg) is not None:
        scope += f"/resourceGroups/{rg}"
    az.error = None
    print(f"[INFO] Policy preflight for '{args.env}' at {scope}")

    assignments = az.run("policy", "assignment", "list", "--scope", scope, "--disable-scope-strict-match")
    if assignments is None:
        print(f"[WARN] couldn't list policy assignments ({az.error}); preflight skipped")
        return 0
    exemptions = az.run("policy", "exemption", "list", "--scope", scope, "--disable-scope-strict-match") or []

    enforced = [a for a in assignments if (a.get("enforcementMode") or "Default") == "Default"]
    hits = find_hits(enforced, scope, az.load_set, az.load_definition)
    now = datetime.datetime.now(datetime.timezone.utc)
    blocking = 0
    for check, a, ref_id, effect in hits:
        name = a.get("displayName") or a.get("name")
        where = f"{name} ({a.get('scope') or a.get('id')})"
        if effect in ("disabled", "audit", "auditifnotexists", "auditifnotexist", "manual"):
            print(f"[OK]   {check['name']}: effect {effect} via {where}")
            continue
        ex = exempted(a["id"], ref_id, exemptions, now)
        if ex:
            print(f"[OK]   {check['name']}: exempted by {ex.get('name')} ({ex.get('exemptionCategory')}) via {where}")
            continue
        blocking += 1
        print(f"[FAIL] {check['name']}: effect {effect} via {where}"
              + (f", reference {ref_id}" if ref_id else ""))
        print(f"       Affects: {check['affects']}.")
        print(f"       Why: {check['why']}")
        print(f"       Ask the platform team for an exemption ({check['request']}), e.g.:")
        print(f"         az policy exemption create --name aigw-{guid_of(check['id'])[:8]} \\")
        print(f"           --policy-assignment {a['id']} \\")
        if ref_id:
            print(f"           --policy-definition-reference-ids {ref_id} \\")
        print("           --exemption-category Mitigated --scope <workload resource group or APIM service id> \\")
        print('           --description "Backends authenticate with the APIM managed identity"')
    if not hits:
        print("[OK]   none of the known policies applies at this scope")
    if blocking:
        print(f"[FAIL] {blocking} blocking finding(s): the apply would fail partway. Resolve them first"
              " (or re-run with --no-fail / PREFLIGHT=false to deploy anyway).")
        return 0 if args.no_fail else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
