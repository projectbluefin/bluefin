"""Unit coverage for scripts/check-testsuite-workflow-ref.py.

The script is a required pr-validation gate. These tests drive its main()
against synthetic workflow directories so every error branch is executed.
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "check-testsuite-workflow-ref.py"

WRAPPER_OK = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: v1
"""


def load_checker(workflow_dir: Path):
    """Load the gate script with its path constants rebound to workflow_dir."""
    spec = importlib.util.spec_from_file_location("testsuite_workflow_ref", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.ROOT = workflow_dir.parent
    module.WORKFLOW_DIR = workflow_dir
    module.WRAPPER = workflow_dir / "run-testsuite.yml"
    return module


class TestsuiteWorkflowRefTests(unittest.TestCase):
    def run_gate(self, files: dict[str, str]) -> int:
        with tempfile.TemporaryDirectory() as directory:
            workflow_dir = Path(directory) / ".github" / "workflows"
            workflow_dir.mkdir(parents=True)
            for name, content in files.items():
                (workflow_dir / name).write_text(content, encoding="utf-8")
            return load_checker(workflow_dir).main()

    def test_accepts_canonical_wrapper(self) -> None:
        self.assertEqual(self.run_gate({"run-testsuite.yml": WRAPPER_OK}), 0)

    def test_accepts_other_workflows_calling_the_local_wrapper(self) -> None:
        caller = """\
jobs:
  tests:
    uses: ./.github/workflows/run-testsuite.yml
"""
        self.assertEqual(
            self.run_gate({"run-testsuite.yml": WRAPPER_OK, "nightly.yml": caller}), 0
        )

    def test_rejects_wrapper_pinned_off_v1(self) -> None:
        wrapper = WRAPPER_OK.replace("e2e.yml@v1", "e2e.yml@main")
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 1)

    def test_rejects_wrapper_with_no_testsuite_reference(self) -> None:
        wrapper = """\
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - run: echo nothing
"""
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 1)

    def test_rejects_wrapper_with_duplicate_testsuite_references(self) -> None:
        wrapper = WRAPPER_OK + """\
  e2e-again:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: v1
"""
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 1)

    def test_rejects_wrapper_passing_a_non_v1_test_ref(self) -> None:
        wrapper = WRAPPER_OK.replace("test_ref: v1", "test_ref: main")
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 1)

    def test_rejects_wrapper_missing_test_ref(self) -> None:
        wrapper = """\
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
"""
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 1)

    def test_rejects_another_workflow_calling_testsuite_directly(self) -> None:
        bypass = """\
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: v1
"""
        self.assertEqual(
            self.run_gate({"run-testsuite.yml": WRAPPER_OK, "nightly.yml": bypass}), 1
        )

    def test_scans_yaml_suffixed_workflows_too(self) -> None:
        bypass = """\
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
"""
        self.assertEqual(
            self.run_gate({"run-testsuite.yml": WRAPPER_OK, "legacy.yaml": bypass}), 1
        )

    def test_comment_suffixed_ref_is_read_without_the_comment(self) -> None:
        wrapper = """\
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1 # pinned
    with:
      test_ref: v1 # pinned
"""
        self.assertEqual(self.run_gate({"run-testsuite.yml": wrapper}), 0)

    def test_repository_workflows_satisfy_the_contract(self) -> None:
        spec = importlib.util.spec_from_file_location("testsuite_ref_live", SCRIPT)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.main(), 0)


if __name__ == "__main__":
    unittest.main()
