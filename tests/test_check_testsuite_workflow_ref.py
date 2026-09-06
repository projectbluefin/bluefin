"""Tests for scripts/check-testsuite-workflow-ref.py.

Enforces that scripts/check-testsuite-workflow-ref.py correctly validates the
Bluefin-to-testsuite reusable workflow contract (@v1 with test_ref: v1, no direct
calls from other workflows).
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT_PATH = ROOT / "scripts" / "check-testsuite-workflow-ref.py"

SPEC = importlib.util.spec_from_file_location("check_testsuite_workflow_ref", SCRIPT_PATH)
assert SPEC and SPEC.loader
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


CANONICAL_WRAPPER = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      image: ${{ inputs.image }}
      test_ref: v1
"""


class CheckTestsuiteWorkflowRefTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_root = Path(self.temp_dir.name)
        self.workflow_dir = self.test_root / ".github" / "workflows"
        self.workflow_dir.mkdir(parents=True)
        self.wrapper_path = self.workflow_dir / "run-testsuite.yml"

        # Patch module-level paths to point into the temporary test workspace
        self.orig_root = checker.ROOT
        self.orig_workflow_dir = checker.WORKFLOW_DIR
        self.orig_wrapper = checker.WRAPPER

        checker.ROOT = self.test_root
        checker.WORKFLOW_DIR = self.workflow_dir
        checker.WRAPPER = self.wrapper_path

    def tearDown(self) -> None:
        checker.ROOT = self.orig_root
        checker.WORKFLOW_DIR = self.orig_workflow_dir
        checker.WRAPPER = self.orig_wrapper
        self.temp_dir.cleanup()

    def run_checker(self) -> tuple[int, str, str]:
        stdout_buf = io.StringIO()
        stderr_buf = io.StringIO()
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        try:
            sys.stdout = stdout_buf
            sys.stderr = stderr_buf
            exit_code = checker.main()
        finally:
            sys.stdout = orig_stdout
            sys.stderr = orig_stderr
        return exit_code, stdout_buf.getvalue(), stderr_buf.getvalue()

    def test_repo_canonical_wrapper_passes(self) -> None:
        """Run checker against the actual repo files and verify pass."""
        checker.ROOT = self.orig_root
        checker.WORKFLOW_DIR = self.orig_workflow_dir
        checker.WRAPPER = self.orig_wrapper

        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 0)
        self.assertIn("Testsuite workflow contract passed", stdout)
        self.assertEqual(stderr, "")

    def test_canonical_wrapper_fixture_passes(self) -> None:
        self.wrapper_path.write_text(CANONICAL_WRAPPER, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 0)
        self.assertIn("Testsuite workflow contract passed", stdout)
        self.assertEqual(stderr, "")

    def test_wrapper_ref_with_comment_and_whitespace(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses:   projectbluefin/testsuite/.github/workflows/e2e.yml@v1   # managed tag
    with:
      test_ref:   v1   # aligned ref
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 0)
        self.assertIn("Testsuite workflow contract passed", stdout)
        self.assertEqual(stderr, "")

    def test_wrapper_pinned_to_non_v1_fails(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@main
    with:
      test_ref: v1
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("must contain exactly one direct testsuite workflow reference at @v1", stderr)
        self.assertIn("found ['main']", stderr)

    def test_wrapper_with_zero_workflow_refs_fails(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    with:
      test_ref: v1
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("must contain exactly one direct testsuite workflow reference at @v1; found []", stderr)

    def test_wrapper_with_multiple_workflow_refs_fails(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e-1:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: v1
  e2e-2:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: v1
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("found ['v1', 'v1']", stderr)

    def test_wrapper_with_non_v1_test_ref_fails(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
    with:
      test_ref: main
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("must pass exactly one test_ref: v1", stderr)
        self.assertIn("found ['main']", stderr)

    def test_wrapper_with_zero_test_refs_fails(self) -> None:
        content = """\
name: Run Testsuite
on:
  workflow_call:
jobs:
  e2e:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
"""
        self.wrapper_path.write_text(content, encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("must pass exactly one test_ref: v1; found []", stderr)

    def test_direct_call_in_other_yml_workflow_fails(self) -> None:
        self.wrapper_path.write_text(CANONICAL_WRAPPER, encoding="utf-8")
        other = self.workflow_dir / "other.yml"
        other.write_text("""\
name: Other
jobs:
  direct:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
""", encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("calls testsuite e2e directly", stderr)
        self.assertIn(str(other.relative_to(self.test_root)), stderr)

    def test_direct_call_in_other_yaml_workflow_fails(self) -> None:
        self.wrapper_path.write_text(CANONICAL_WRAPPER, encoding="utf-8")
        other = self.workflow_dir / "other.yaml"
        other.write_text("""\
name: Other YAML
jobs:
  direct:
    uses: projectbluefin/testsuite/.github/workflows/e2e.yml@v1
""", encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("calls testsuite e2e directly", stderr)
        self.assertIn(str(other.relative_to(self.test_root)), stderr)

    def test_other_workflow_without_direct_call_passes(self) -> None:
        self.wrapper_path.write_text(CANONICAL_WRAPPER, encoding="utf-8")
        other = self.workflow_dir / "clean.yml"
        other.write_text("""\
name: Clean
on:
  workflow_dispatch:
jobs:
  clean:
    runs-on: ubuntu-latest
    steps:
      - run: echo clean
""", encoding="utf-8")
        code, stdout, stderr = self.run_checker()
        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")


if __name__ == "__main__":
    unittest.main()
