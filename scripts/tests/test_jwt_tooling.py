"""Unit tests for the JWT tooling: scripts/gateway_env.py, entra_id_setup.py and jwt_auth_tests.py
(run: python3 -m unittest discover scripts/tests)."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import entra_id_setup  # noqa: E402
import gateway_env  # noqa: E402
import jwt_auth_tests  # noqa: E402

SUB = "00000000-0000-0000-0000-000000000000"


class Naming(unittest.TestCase):
    # Same inputs and expectations as modules/naming/tests/unit.tftest.hcl: the formulas must match.
    def test_matches_the_naming_module(self):
        n = gateway_env.names(SUB, "aigw", "dev")
        self.assertEqual(n["gateway_app"], "app-aigw-dev-27cbb-gateway")
        self.assertEqual(n["apim"], "apim-aigw-dev-27cbb")
        self.assertEqual(n["key_vault"], "kv-aigw-dev-27cbb")
        self.assertEqual(n["resource_group"], "rg-aigw-dev")

    def test_seed_and_overrides(self):
        n = gateway_env.names(SUB, "aigw", "dev", "k3x9p", {"apim": "apim-custom", "key_vault": ""})
        self.assertEqual(n["apim"], "apim-custom")
        self.assertEqual(n["key_vault"], "kv-aigw-dev-k3x9p")

    def test_reads_the_naming_block_of_common_tfvars(self):
        text = 'workload = "aigw"\nnaming = {\n  unique_seed = "k3x9p"\n  name_overrides = {\n    apim = "apim-x"\n    gateway_app = "app-y"\n  }\n}\n'
        self.assertEqual(gateway_env.read_naming(text), ("k3x9p", {"apim": "apim-x", "gateway_app": "app-y"}))
        self.assertEqual(gateway_env.read_naming('workload = "aigw"\n'), (None, {}))


class EntraSetup(unittest.TestCase):
    ROLES = [{"id": rid, "value": value, "isEnabled": True} for rid, _, value, _ in entra_id_setup.APP_ROLES]

    def test_gateway_app_matches_the_terraform_module(self):
        body = entra_id_setup.gateway_app_body("app-aigw-dev-27cbb-gateway")
        self.assertEqual(body["api"]["requestedAccessTokenVersion"], 2)
        self.assertEqual(body["signInAudience"], "AzureADMyOrg")
        self.assertEqual([r["value"] for r in body["appRoles"]], ["Task.ReadWrite", "Models.Read", "MCP.Read", "Agent.Read"])
        self.assertEqual(body["api"]["oauth2PermissionScopes"][0]["value"], "access_as_user")
        # modules/gateway-entra-app uses the same canonical IDs.
        tf = (pathlib.Path(__file__).resolve().parents[2] / "modules/gateway-entra-app/main.tf").read_text()
        for rid, *_ in entra_id_setup.APP_ROLES + [(entra_id_setup.SCOPE_ID,)]:
            self.assertIn(rid, tf)

    def test_role_changes_are_exact(self):
        ids = {r["value"]: r["id"] for r in self.ROLES}
        add, remove = entra_id_setup.role_changes(self.ROLES, [ids["Task.ReadWrite"]], ["Models.Read"])
        self.assertEqual((add, remove), ([ids["Models.Read"]], [ids["Task.ReadWrite"]]))
        self.assertEqual(entra_id_setup.role_changes(self.ROLES, [ids["Models.Read"]], ["Models.Read"]), ([], []))
        self.assertEqual(entra_id_setup.role_changes(self.ROLES, [ids["Models.Read"]], []), ([], [ids["Models.Read"]]))

    def test_role_changes_ignore_other_apps_and_reject_unknown_roles(self):
        add, remove = entra_id_setup.role_changes(self.ROLES, ["11111111-0000-0000-0000-000000000000"], ["Agent.Read"])
        self.assertEqual(remove, [])
        with self.assertRaises(ValueError):
            entra_id_setup.role_changes(self.ROLES, [], ["Admin"])


class JwtTests(unittest.TestCase):
    GATEWAY = {"audience": "a1", "issuer": "https://login.microsoftonline.com/t/v2.0",
               "openid_config_url": "https://login.microsoftonline.com/t/v2.0/.well-known/openid-configuration"}

    def test_reads_the_generated_product_policy(self):
        xml = ('<policies><inbound><base />\n<set-variable name="jwtRequired" value="true" />\n'
               '<set-variable name="requiredRoles" value="Models.Read,Agent.Read" />\n'
               '<set-variable name="allowedModels" value="gpt-5.4-mini,fast" /></inbound></policies>')
        s = jwt_auth_tests.policy_settings(xml)
        self.assertTrue(s["jwt_required"])
        self.assertEqual(s["required_roles"], ["Models.Read", "Agent.Read"])
        self.assertEqual(s["allowed_models"], ["gpt-5.4-mini", "fast"])
        self.assertFalse(jwt_auth_tests.policy_settings("<policies />")["jwt_required"])

    def test_the_module_template_and_the_parser_agree(self):
        tpl = (pathlib.Path(__file__).resolve().parents[2] / "modules/access-contract/policies/product-policy.xml.tftpl").read_text()
        for var in ("jwtRequired", "jwtAudience", "jwtIssuer", "jwtOpenIdConfigUrl", "requiredRoles"):
            self.assertIn(f'<set-variable name="{var}" value="', tpl)

    def test_policy_response_as_xml_or_json(self):
        xml = '<policies><set-variable name="jwtRequired" value="true" /></policies>'
        self.assertEqual(jwt_auth_tests.policy_text(xml), xml)
        self.assertEqual(jwt_auth_tests.policy_text('{"properties": {"format": "xml", "value": "<policies />"}}'), "<policies />")
        self.assertEqual(jwt_auth_tests.policy_text(None), "")

    def test_cases_for_a_jwt_product(self):
        s = jwt_auth_tests.policy_settings('<set-variable name="jwtRequired" value="true" />')
        cases = jwt_auth_tests.plan_cases(s, [], True)
        self.assertEqual([(c[0], c[3]) for c in cases], [("T1", 200), ("T2", 401), ("T3", 401), ("T4", 401)])

    def test_cases_for_a_role_product(self):
        s = jwt_auth_tests.policy_settings('<set-variable name="jwtRequired" value="true" /><set-variable name="requiredRoles" value="Models.Read" />')
        first = jwt_auth_tests.plan_cases(s, ["models.read"], True)[0]
        self.assertEqual((first[0], first[3]), ("T5", 200))
        self.assertEqual(jwt_auth_tests.plan_cases(s, ["Agent.Read"], True)[0][3], 403)
        self.assertEqual(jwt_auth_tests.plan_cases(s, [], True)[1][0], "T7")

    def test_another_identity_provider_gets_negative_tests_only(self):
        s = jwt_auth_tests.policy_settings('<set-variable name="jwtRequired" value="true" /><set-variable name="jwtAudience" value="https://my-api.example.com" />')
        self.assertFalse(jwt_auth_tests.uses_gateway_idp(s, self.GATEWAY))
        self.assertTrue(all(c[3] == 401 for c in jwt_auth_tests.plan_cases(s, [], False)))
        same = jwt_auth_tests.policy_settings(f'<set-variable name="jwtRequired" value="true" /><set-variable name="jwtAudience" value="a1" />')
        self.assertTrue(jwt_auth_tests.uses_gateway_idp(same, self.GATEWAY))

    def test_requests_per_api(self):
        gw = "https://apim.azure-api.net"
        self.assertEqual(jwt_auth_tests.request_for("azure-openai-api", "openai", gw, "gpt-5.4-mini")[0],
                         f"{gw}/openai/deployments/gpt-5.4-mini/chat/completions?api-version={jwt_auth_tests.AOAI_API_VERSION}")
        url, body = jwt_auth_tests.request_for("universal-llm-api", "models", gw, "fast")
        self.assertEqual((url, body["model"]), (f"{gw}/models/chat/completions", "fast"))
        self.assertEqual(jwt_auth_tests.request_for("unified-ai-api", "unified-ai", gw, "m")[0], f"{gw}/unified-ai/v1/chat/completions")
        self.assertIsNone(jwt_auth_tests.request_for("weather-api", "weather", gw, "m"))

    def test_token_claims(self):
        import base64
        import json
        payload = base64.urlsafe_b64encode(json.dumps({"aud": "a1", "roles": ["Models.Read"]}).encode()).decode().rstrip("=")
        self.assertEqual(jwt_auth_tests.token_claims(f"h.{payload}.s")["roles"], ["Models.Read"])
        self.assertEqual(jwt_auth_tests.token_claims("garbage"), {})


if __name__ == "__main__":
    unittest.main()
