import importlib.util
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("apply_stack", Path(__file__).parents[1] / "apply-stack.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
TARGET = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Web/sites/site"
SETTING_ID = f"{TARGET}/providers/Microsoft.Insights/diagnosticSettings/diag-site"


def plan(target=TARGET, actions=None, resource_type="azurerm_monitor_diagnostic_setting"):
    return {"resource_changes": [{
        "address": "module.logic_app.azurerm_monitor_diagnostic_setting.logic_app[0]",
        "type": resource_type,
        "change": {
            "actions": actions or ["create"],
            "after": {"name": "diag-site", "target_resource_id": target},
            "after_unknown": {"target_resource_id": target is None},
        },
    }]}


class DiagnosticAdoptionTests(unittest.TestCase):
    @patch.object(runner.subprocess, "run")
    def test_exact_setting_is_imported_using_provider_id(self, run):
        run.side_effect = [
            subprocess.CompletedProcess([], 0, json.dumps({"id": SETTING_ID}), ""),
            subprocess.CompletedProcess([], 0),
        ]
        self.assertEqual(runner.adopt_diagnostics(Path("stack"), plan(), ["-var-file=common.tfvars"]), 1)
        query, imported = [call.args[0] for call in run.call_args_list]
        self.assertEqual(query[5], f"{SETTING_ID}?api-version=2021-05-01-preview")
        self.assertEqual(imported[-1], f"{TARGET}|diag-site")
        self.assertIn("-var-file=common.tfvars", imported)
        self.assertEqual(imported[-2], plan()["resource_changes"][0]["address"])

    @patch.object(runner.subprocess, "run")
    def test_unknown_target_is_deferred(self, run):
        self.assertEqual(runner.adopt_diagnostics(Path("stack"), plan(target=None), []), 0)
        run.assert_not_called()

    @patch.object(runner.subprocess, "run")
    def test_only_missing_resource_is_ignored(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, "", "ERROR: (ResourceNotFound) missing")
        self.assertEqual(runner.adopt_diagnostics(Path("stack"), plan(), []), 0)
        run.return_value = subprocess.CompletedProcess([], 1, "", "ERROR: (AuthorizationFailed) denied")
        with self.assertRaises(subprocess.CalledProcessError):
            runner.adopt_diagnostics(Path("stack"), plan(), [])

    @patch.object(runner.subprocess, "run")
    def test_other_setting_is_not_adopted(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({"id": SETTING_ID + "-policy"}), "")
        with self.assertRaises(ValueError):
            runner.adopt_diagnostics(Path("stack"), plan(), [])
        self.assertEqual(run.call_count, 1)

    @patch.object(runner.subprocess, "run")
    def test_updates_replacements_destroy_and_other_types_are_not_adopted(self, run):
        for actions in (["update"], ["delete", "create"], ["delete"]):
            self.assertEqual(runner.adopt_diagnostics(Path("stack"), plan(actions=actions), []), 0)
        self.assertEqual(runner.adopt_diagnostics(Path("stack"), plan(resource_type="azapi_resource_action"), []), 0)
        run.assert_not_called()

    def test_import_only_receives_variables_not_plan_options(self):
        self.assertEqual(runner.import_arguments([
            "-target=module.logic_app", "-var-file", "common.tfvars", "-parallelism=2",
            "-var=code_deploy=false", "-var-file=platform.tfvars",
        ]), ["-var-file", "common.tfvars", "-var=code_deploy=false", "-var-file=platform.tfvars"])

    def test_arm_json_errors_are_classified_by_code_not_message(self):
        self.assertTrue(runner.resource_missing('ERROR: Not Found({"error":{"code":"ResourceNotFound"}})'))
        self.assertFalse(runner.resource_missing('ERROR: Forbidden({"error":{"code":"AuthorizationFailed","message":"ResourceNotFound"}})'))
        self.assertFalse(runner.resource_missing("ERROR: connection reset"))

    @patch.object(runner, "replan")
    @patch.object(runner, "adopt_diagnostics")
    @patch.object(runner, "read_plan")
    @patch.object(runner.subprocess, "run")
    def test_partial_apply_recovers_once_and_replans_after_import(self, run, read, adopt, replan):
        read.side_effect = [plan(target=None), plan()]
        adopt.side_effect = [0, 1]
        run.side_effect = [subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0)]
        self.assertEqual(runner.apply(Path("stack"), ["-var-file=x"]), 0)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(replan.call_count, 2)
        self.assertEqual(adopt.call_count, 2)

    @patch.object(runner, "replan")
    @patch.object(runner, "adopt_diagnostics", return_value=0)
    @patch.object(runner, "read_plan", return_value=plan())
    @patch.object(runner.subprocess, "run")
    def test_no_recovery_does_not_retry_failed_apply(self, run, read, adopt, replan):
        run.return_value = subprocess.CompletedProcess([], 7)
        self.assertEqual(runner.apply(Path("stack"), []), 7)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(replan.call_count, 1)

    @patch.object(runner, "replan")
    @patch.object(runner, "adopt_diagnostics", return_value=1)
    @patch.object(runner, "read_plan", return_value=plan(actions=["update"]))
    @patch.object(runner.subprocess, "run")
    def test_preflight_import_replans_before_apply(self, run, read, adopt, replan):
        run.return_value = subprocess.CompletedProcess([], 0)
        self.assertEqual(runner.apply(Path("stack"), []), 0)
        replan.assert_called_once()
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
