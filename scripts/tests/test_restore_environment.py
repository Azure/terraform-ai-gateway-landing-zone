import importlib.util
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("restore_environment", Path(__file__).parents[1] / "restore-environment.py")
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class EnvironmentTests(unittest.TestCase):
    def test_restores_only_environment_inputs(self):
        files = {
            "common.tfvars": 'environment = "dev"',
            "backend.hcl": 'storage_account_name = "state"',
            "platform.tfvars": "features = {}",
            "access-contracts/team-a.tfvars": "services = []",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            restore.restore("dev", files, root)
            for name, content in files.items():
                self.assertEqual((root / "environments" / "dev" / name).read_text(), content)

    def test_rejects_invalid_config_without_writing_files(self):
        for environment, files in (
            ("../dev", {"common.tfvars": "", "backend.hcl": ""}),
            ("dev", {"common.tfvars": ""}),
            ("dev", {"common.tfvars": "", "backend.hcl": "", "../../evil.tf": ""}),
            ("dev", {"common.tfvars": "", "backend.hcl": "", "main.tf": ""}),
            ("dev", {"common.tfvars": 4, "backend.hcl": ""}),
        ):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with self.assertRaises(ValueError):
                    restore.restore(environment, files, root)
                self.assertFalse((root / "environments").exists())


if __name__ == "__main__":
    unittest.main()
