"""Shared helpers for the gateway scripts: environment resolution (environments/<env>/common.tfvars
and the naming contract of modules/naming) and Azure CLI / Microsoft Graph calls.

Standard library only; Azure access goes through the az CLI (az login).
"""
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRAPH = "https://graph.microsoft.com/v1.0"


def read_tfvar(text, key):
    """A top-level string variable (key = "value") of a .tfvars file."""
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    return m.group(1) if m else None


def read_naming(text):
    """naming = { unique_seed = "...", name_overrides = { role = "name", ... } } of common.tfvars."""
    m = re.search(r"^\s*naming\s*=\s*\{(.*?)^\}", text, re.MULTILINE | re.DOTALL)
    if not m:
        return None, {}
    block = m.group(1)
    seed = read_tfvar(block, "unique_seed")
    overrides = {}
    o = re.search(r"name_overrides\s*=\s*\{(.*?)\}", block, re.DOTALL)
    if o:
        overrides = dict(re.findall(r'([A-Za-z0-9_]+)\s*=\s*"([^"]*)"', o.group(1)))
    return seed, overrides


def names(subscription_id, workload, environment, unique_seed=None, overrides=None):
    """The names of modules/naming this tooling needs (same formula: keep them in sync)."""
    seed = unique_seed or hashlib.sha256(f"{subscription_id}/{workload}/{environment}".encode()).hexdigest()[:5]
    base = f"{workload}-{environment}"
    generated = {
        "resource_group": f"rg-{base}",
        "apim": f"apim-{base}-{seed}",
        "key_vault": f"kv-{base[:14]}-{seed}",
        "gateway_app": f"app-{base}-{seed}-gateway",
    }
    generated.update({k: v for k, v in (overrides or {}).items() if v})
    return generated


class Env:
    """environments/<env>: subscription, workload, environment and the derived names."""

    def __init__(self, env):
        path = ROOT / "environments" / env / "common.tfvars"
        if not path.exists():
            raise SystemExit(f"[FAIL] {path} not found (copy an example to environments/{env}/ first)")
        text = path.read_text()
        self.env = env
        self.subscription_id = read_tfvar(text, "subscription_id")
        self.workload = read_tfvar(text, "workload")
        self.environment = read_tfvar(text, "environment")
        if not (self.subscription_id and self.workload and self.environment):
            raise SystemExit(f"[FAIL] {path}: subscription_id, workload and environment are required")
        seed, overrides = read_naming(text)
        self.names = names(self.subscription_id, self.workload, self.environment, seed, overrides)


class AzError(Exception):
    pass


class Az:
    """Thin az CLI wrapper: JSON in, JSON out, never prompts."""

    def __init__(self, subscription_id=None):
        self.exe = shutil.which("az")
        if not self.exe:
            raise SystemExit("[FAIL] az CLI not found (https://aka.ms/installazurecli)")
        self.subscription_id = subscription_id

    def run(self, *args, check=True, raw=False):
        p = subprocess.run([self.exe, *args, "-o", "json", "--only-show-errors"],
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if p.returncode != 0:
            msg = p.stderr.strip().splitlines()[-1] if p.stderr.strip() else f"exit {p.returncode}"
            if check:
                raise AzError(f"az {' '.join(args[:3])}: {msg}")
            return None
        out = p.stdout.strip().lstrip("\ufeff")  # some APIM responses (product policies) start with a BOM
        if raw:
            return out
        return json.loads(out) if out else None

    def rest(self, method, url, body=None, check=True, raw=False):
        """az rest with the body in a temporary file (no shell quoting, nothing on the command line).
        raw=True returns the response text (e.g. a policy APIM answers as XML instead of JSON)."""
        args = ["rest", "--method", method, "--url", url]
        tmp = None
        if body is not None:
            fd, tmp = tempfile.mkstemp(suffix=".json")
            with os.fdopen(fd, "w") as f:
                json.dump(body, f)
            args += ["--headers", "Content-Type=application/json", "--body", f"@{tmp}"]
        try:
            return self.run(*args, check=check, raw=raw)
        finally:
            if tmp:
                os.unlink(tmp)

    def arm(self, path):
        """Management-plane URL for a path under the subscription."""
        return f"https://management.azure.com/subscriptions/{self.subscription_id}{path}"
