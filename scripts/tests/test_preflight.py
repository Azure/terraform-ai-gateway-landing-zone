"""Unit tests for scripts/preflight.py (run: python3 -m unittest discover scripts/tests)."""
import datetime
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import preflight  # noqa: E402

CHECK_ID = "c15dcc82-b93c-4dcb-9332-fbf121685b54"
SET_ID = "/providers/Microsoft.Authorization/policySetDefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8"
ASSIGNMENT_ID = "/providers/Microsoft.Management/managementGroups/ADCB/providers/Microsoft.Authorization/policyAssignments/Deploy-ASC-Monitoring"
REF = "aPIManagementServiceShouldHaveBackendCallsAuthenticated"
RG = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-aigw-dev"
NOW = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)


def assignment(**over):
    a = {"id": ASSIGNMENT_ID, "name": "Deploy-ASC-Monitoring", "displayName": "Microsoft Cloud Security Benchmark",
         "scope": "/providers/Microsoft.Management/managementGroups/ADCB", "policyDefinitionId": SET_ID,
         "enforcementMode": "Default", "notScopes": [], "parameters": {}}
    a.update(over)
    return a


def initiative(ref_parameters, set_parameters=None):
    return {
        "parameters": set_parameters or {},
        "policyDefinitions": [
            {"policyDefinitionId": f"/providers/Microsoft.Authorization/policyDefinitions/{CHECK_ID}",
             "policyDefinitionReferenceId": REF, "parameters": ref_parameters},
            {"policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/other", "policyDefinitionReferenceId": "x"},
        ],
    }


class Hits(unittest.TestCase):
    def hits(self, pset, definition=None, **over):
        return preflight.find_hits([assignment(**over)], RG, lambda _: pset, lambda _: definition)

    def test_literal_effect(self):
        (check, a, ref, effect), = self.hits(initiative({"effect": {"value": "Deny"}}))
        self.assertEqual((check["id"], ref, effect), (CHECK_ID, REF, "deny"))

    def test_effect_from_assignment_parameter(self):
        pset = initiative({"effect": {"value": "[parameters('apiEffect')]"}}, {"apiEffect": {"defaultValue": "Audit"}})
        self.assertEqual(self.hits(pset, parameters={"apiEffect": {"value": "Deny"}})[0][3], "deny")

    def test_effect_from_initiative_default(self):
        pset = initiative({"effect": {"value": "[parameters('apiEffect')]"}}, {"apiEffect": {"defaultValue": "Audit"}})
        self.assertEqual(self.hits(pset)[0][3], "audit")

    def test_effect_from_definition_default_when_reference_has_none(self):
        definition = {"parameters": {"effect": {"defaultValue": "Deny"}}}
        self.assertEqual(self.hits(initiative({}), definition)[0][3], "deny")

    def test_unknown_effect(self):
        self.assertEqual(self.hits(initiative({}), None)[0][3], "unknown")

    def test_direct_assignment(self):
        definition = {"parameters": {"effect": {"defaultValue": "Deny"}}}
        a = assignment(policyDefinitionId=f"/providers/Microsoft.Authorization/policyDefinitions/{CHECK_ID}")
        hits = preflight.find_hits([a], RG, lambda _: None, lambda _: definition)
        self.assertEqual(hits[0][3], "deny")

    def test_assignment_override_wins_over_defaults(self):
        override = [{"kind": "policyEffect", "value": "Deny", "selectors": [{"kind": "policyDefinitionReferenceId", "in": [REF]}]}]
        pset = initiative({})
        self.assertEqual(self.hits(pset, {"parameters": {"effect": {"defaultValue": "Audit"}}}, overrides=override)[0][3], "deny")

    def test_override_for_another_reference_is_ignored(self):
        override = [{"kind": "policyEffect", "value": "Deny", "selectors": [{"kind": "policyDefinitionReferenceId", "in": ["other"]}]}]
        definition = {"parameters": {"effect": {"defaultValue": "Audit"}}}
        self.assertEqual(self.hits(initiative({}), definition, overrides=override)[0][3], "audit")

    def test_override_without_selector_applies_to_all(self):
        definition = {"parameters": {"effect": {"defaultValue": "Audit"}}}
        override = [{"kind": "policyEffect", "value": "Deny"}]
        self.assertEqual(self.hits(initiative({}), definition, overrides=override)[0][3], "deny")

    def test_not_scopes_skip(self):
        self.assertEqual(self.hits(initiative({"effect": {"value": "Deny"}}), notScopes=[RG]), [])

    def test_other_policies_ignored(self):
        pset = {"policyDefinitions": [{"policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/other"}]}
        self.assertEqual(self.hits(pset), [])


class Exemptions(unittest.TestCase):
    def exemption(self, **over):
        e = {"name": "ex", "policyAssignmentId": ASSIGNMENT_ID, "policyDefinitionReferenceIds": [REF], "exemptionCategory": "Mitigated"}
        e.update(over)
        return e

    def test_matches_reference(self):
        self.assertIsNotNone(preflight.exempted(ASSIGNMENT_ID, REF, [self.exemption()], NOW))

    def test_whole_assignment(self):
        self.assertIsNotNone(preflight.exempted(ASSIGNMENT_ID, REF, [self.exemption(policyDefinitionReferenceIds=None)], NOW))

    def test_other_reference_does_not_match(self):
        self.assertIsNone(preflight.exempted(ASSIGNMENT_ID, REF, [self.exemption(policyDefinitionReferenceIds=["other"])], NOW))

    def test_expired(self):
        self.assertIsNone(preflight.exempted(ASSIGNMENT_ID, REF, [self.exemption(expiresOn="2025-01-01T00:00:00Z")], NOW))

    def test_other_assignment(self):
        self.assertIsNone(preflight.exempted(ASSIGNMENT_ID, REF, [self.exemption(policyAssignmentId="/other")], NOW))


class Helpers(unittest.TestCase):
    def test_read_tfvar(self):
        text = 'workload = "aigw"\n  subscription_id = "abc"  # c\n'
        self.assertEqual((preflight.read_tfvar(text, "workload"), preflight.read_tfvar(text, "subscription_id"),
                          preflight.read_tfvar(text, "missing")), ("aigw", "abc", None))

    def test_guid_of(self):
        self.assertEqual(preflight.guid_of(SET_ID + "/"), "1f3afdf9-d0c9-4c3d-847f-89da613e70a8")


if __name__ == "__main__":
    unittest.main()
