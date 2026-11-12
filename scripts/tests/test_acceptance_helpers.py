"""Unit tests for validation/shared/acceptance.py, the helpers of citadel-acceptance-tests.ipynb
(run: python3 -m unittest discover scripts/tests). No Azure access: pure functions only."""
import csv
import io
import pathlib
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "validation" / "shared"))
import acceptance as A  # noqa: E402

try:
    import hcl2  # noqa: F401
    HAS_HCL2 = True
except ImportError:
    HAS_HCL2 = False


def run_case(results, case_id, body):
    with redirect_stdout(io.StringIO()):
        with results.case(case_id) as t:
            body(t)
    return results.rows[case_id]


class Registry(unittest.TestCase):
    def test_statuses(self):
        r = A.Results("dev")
        self.assertEqual(run_case(r, "AUTH-001", lambda t: t.check(True, "ok"))["status"], A.PASS)
        self.assertEqual(run_case(r, "AUTH-003", lambda t: (t.check(True, "a"), t.check(False, "b")))["status"], A.FAIL)
        self.assertEqual(run_case(r, "AUTH-009", lambda t: t.skip("opt-in"))["status"], A.SKIPPED)
        self.assertEqual(run_case(r, "POL-002", lambda t: t.not_configured("no pii", A.SNIPPETS["pii"]))["status"], A.NOT_CONFIGURED)
        self.assertEqual(run_case(r, "PBI-002", lambda t: t.manual("look"))["status"], A.MANUAL)
        self.assertEqual(run_case(r, "PBI-007", lambda t: 1 / 0)["status"], A.ERROR)
        self.assertEqual(run_case(r, "PBI-010", lambda t: None)["status"], A.MANUAL)

    def test_keyboard_interrupt_propagates(self):
        def interrupt(_):
            raise KeyboardInterrupt
        with self.assertRaises(KeyboardInterrupt):
            run_case(A.Results("dev"), "AUTH-001", interrupt)

    def test_unknown_case(self):
        with self.assertRaises(KeyError):
            A.Results("dev").case("NOPE-1")

    def test_export_lists_every_case_in_catalogue_order(self):
        r = A.Results("dev")
        run_case(r, "SEC-001", lambda t: (t.record("access", {"kv": "private"}), t.check(True, "ok")))
        tmp = tempfile.mkdtemp()
        try:
            path = r.export_csv(tmp)
            with path.open(encoding="utf-8") as f:
                rows = list(csv.DictReader(f))
        finally:
            shutil.rmtree(tmp)
        self.assertEqual([x["id"] for x in rows], [c[0] for c in A.CASES])
        sec = next(x for x in rows if x["id"] == "SEC-001")
        self.assertEqual(sec["status"], A.PASS)
        self.assertIn('"kv": "private"', sec["evidence"])
        self.assertEqual(next(x for x in rows if x["id"] == "AUTH-001")["status"], A.NOT_RUN)


class Policies(unittest.TestCase):
    POLICY = """<policies><inbound><base />
      <set-variable name="jwtRequired" value="true" />
      <set-variable name="piiAnonymizationEnabled" value="true" />
      <include-fragment fragment-id="pii-anonymization" />
      <llm-content-safety backend-id="content-safety-backend" shield-prompt="true" enforce-on-completions="false">
      </llm-content-safety>
      <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="300" token-quota="2000"
                       token-quota-period="Hourly" estimate-prompt-tokens="false" />
    </inbound></policies>"""

    def test_token_limit(self):
        tl = A.token_limit(self.POLICY)
        self.assertEqual((tl["tokens-per-minute"], tl["token-quota"], tl["token-quota-period"]), ("300", "2000", "Hourly"))
        self.assertEqual(A.token_limit("<policies/>"), {})

    def test_features(self):
        f = A.features(self.POLICY)
        self.assertTrue(f["pii"] and f["content_safety"] and f["shield_prompt"])
        self.assertFalse(f["content_safety_completions"] or f["semantic_cache"] or f["pii_blocking"])
        self.assertTrue(A.features('<llm-semantic-cache-lookup score-threshold="0.05">')["semantic_cache"])
        self.assertTrue(A.features('<include-fragment fragment-id="security-handler" />')["jwt_validation"])
        self.assertFalse(A.features("<policies><inbound><base /></inbound></policies>")["jwt_validation"])

    def test_models_from_fragment(self):
        xml = "// Model: gpt-4o from backend: b1\n// Model: gpt-4o from backend: b2\n// Model: phi-4 from backend: b1"
        self.assertEqual(A.models_from_fragment(xml), ["gpt-4o", "phi-4"])


class Contracts(unittest.TestCase):
    def test_unquote(self):
        self.assertEqual(A.unquote({'"a"': ['"x"', 1, True], "b": {"c": '"y"'}}), {"a": ["x", 1, True], "b": {"c": "y"}})

    @unittest.skipUnless(HAS_HCL2, "python-hcl2 not installed (validation/requirements.txt)")
    def test_product_ids_match_the_access_contract_module(self):
        tmp = pathlib.Path(tempfile.mkdtemp())
        try:
            folder = tmp / "environments" / "qa" / "access-contracts"
            folder.mkdir(parents=True)
            shutil.copy(ROOT / "validation" / "acceptance-contract.tfvars", folder)
            contracts = A.load_contracts("qa", root=tmp)
        finally:
            shutil.rmtree(tmp)
        services = {s["code"]: s for s in contracts[0]["services"]}
        # modules/access-contract: product_id = "<code>-<business_unit>-<use_case_name>-<environment>"
        self.assertEqual(services["RATE"]["product_id"], "RATE-QA-Acceptance-DEV")
        self.assertEqual(services["QUOTA"]["display_name"], "QUOTA QA Acceptance DEV")
        self.assertEqual(services["QUOTA"]["key_secret"], "qa-quota-key")
        self.assertEqual(services["QUOTA"]["token_limit"], {"token_quota": 2000, "token_quota_period": "Hourly"})
        self.assertEqual(services["RATE"]["apis"], ["universal-llm-api", "azure-openai-api"])
        self.assertTrue(contracts[0]["key_vault"]["enabled"])


class Network(unittest.TestCase):
    def res(self, t, props, name="r"):
        return {"type": t, "name": name, "properties": props}

    def test_public_access(self):
        self.assertEqual(A.public_access(self.res("Microsoft.ApiManagement/service", {"virtualNetworkType": "Internal", "publicNetworkAccess": "Enabled"}))[0], "private")
        self.assertEqual(A.public_access(self.res("Microsoft.ApiManagement/service", {"virtualNetworkType": "External"}))[0], "public")
        self.assertEqual(A.public_access(self.res("Microsoft.KeyVault/vaults", {"publicNetworkAccess": "Disabled"}))[0], "private")
        self.assertEqual(A.public_access(self.res("Microsoft.KeyVault/vaults", {"publicNetworkAccess": "Enabled", "networkAcls": {"defaultAction": "Deny", "ipRules": [{"value": "1.2.3.4"}]}}))[0], "restricted")
        self.assertEqual(A.public_access(self.res("Microsoft.DocumentDB/databaseAccounts", {"publicNetworkAccess": "Enabled"}))[0], "public")
        self.assertEqual(A.public_access(self.res("Microsoft.OperationalInsights/workspaces", {"publicNetworkAccessForIngestion": "Disabled", "publicNetworkAccessForQuery": "Enabled"}))[0], "restricted")

    def test_endpoints_and_hosts(self):
        kv = self.res("Microsoft.KeyVault/vaults", {"vaultUri": "https://kv-x.vault.azure.net/"})
        self.assertEqual(A.endpoints(kv), ["https://kv-x.vault.azure.net/"])
        self.assertEqual(A.endpoints(self.res("Microsoft.Search/searchServices", {}, "srch")), ["https://srch.search.windows.net/"])
        self.assertTrue(A.is_azure_host("https://acct.openai.azure.com/openai"))
        self.assertFalse(A.is_azure_host("https://generativelanguage.googleapis.com/v1beta"))

    def test_cognitive_endpoints_exclude_shared_services(self):
        acct = self.res("Microsoft.CognitiveServices/accounts", {
            "customSubDomainName": "aif-x", "endpoint": "https://aif-x.cognitiveservices.azure.com/",
            "endpoints": {"OpenAI": "https://aif-x.openai.azure.com/", "Translator": "https://api.cognitive.microsofttranslator.com/",
                          "Speech": "https://swedencentral.stt.speech.microsoft.com"}}, "aif-x")
        self.assertEqual(A.endpoints(acct), ["https://aif-x.cognitiveservices.azure.com/", "https://aif-x.openai.azure.com/"])

    def test_probe_plan_uses_an_authenticated_data_plane_call(self):
        self.assertEqual(A.probe_plan("https://aif-x.cognitiveservices.azure.com/"),
                         ("https://aif-x.cognitiveservices.azure.com/openai/models?api-version=2024-10-21", "https://cognitiveservices.azure.com"))
        self.assertEqual(A.probe_plan("https://kv-x.vault.azure.net/")[1], "https://vault.azure.net")
        self.assertEqual(A.probe_plan("https://acct.documents.azure.com:443/"), ("https://acct.documents.azure.com/", None))


class Secrets(unittest.TestCase):
    def test_scan_reports_locations_not_values(self):
        key = "f" * 32  # built at runtime: no credential-looking literal in the repository
        jwt = ".".join(["eyJ" + "a" * 20, "eyJ" + "b" * 20, "c" * 20])
        rows = [{"Type": "AppRequests", "Url": f"https://gw/x?api-key={key}"},
                {"Type": "ApiManagementGatewayLogs", "RequestHeaders": f"Bearer {jwt}"},
                {"Type": "AppTraces", "Message": "nothing to see here at all"}]
        hits = A.scan_for_secrets(rows, {"P1 primary key": key})
        self.assertEqual(hits, [("ApiManagementGatewayLogs", "RequestHeaders", "JWT"), ("AppRequests", "Url", "P1 primary key")])
        self.assertNotIn(key, repr(hits))

    def test_fingerprint(self):
        self.assertEqual(len(A.fingerprint("secret")), 8)
        self.assertNotIn("secret", A.fingerprint("secret"))
        self.assertEqual(A.fingerprint(""), "-")


if __name__ == "__main__":
    unittest.main()
