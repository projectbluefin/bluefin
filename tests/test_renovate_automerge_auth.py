import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "check-renovate-automerge-auth.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("renovate_auth", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RenovateAutomergeAuthTests(unittest.TestCase):
    def test_accepts_semantically_correct_flow_style_secrets(self) -> None:
        checker = load_checker()
        workflow = """\
name: Renovate Auto-merge
jobs:
  automerge:
    uses: projectbluefin/actions/.github/workflows/reusable-renovate-automerge.yml@v1
    secrets: {app_id: "${{ secrets.MERGERAPTOR_APP_ID }}", private_key: "${{ secrets.MERGERAPTOR_PRIVATE_KEY }}"}
"""
        with tempfile.TemporaryDirectory() as directory:
            checker.WORKFLOW = Path(directory) / "renovate-automerge.yml"
            checker.WORKFLOW.write_text(workflow, encoding="utf-8")
            self.assertEqual(checker.main(), 0)


if __name__ == "__main__":
    unittest.main()
