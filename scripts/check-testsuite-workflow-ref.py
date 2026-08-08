#!/usr/bin/env python3
"""Enforce the Bluefin-to-testsuite reusable-workflow contract."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
WRAPPER = WORKFLOW_DIR / "run-testsuite.yml"
WORKFLOW_REF = re.compile(
    r"^\s+uses:\s+projectbluefin/testsuite/\.github/workflows/e2e\.yml@([^\s#]+)",
    re.MULTILINE,
)
TEST_REF = re.compile(r"^\s+test_ref:\s+([^\s#]+)", re.MULTILINE)


def main() -> int:
    errors: list[str] = []
    wrapper_refs = WORKFLOW_REF.findall(WRAPPER.read_text(encoding="utf-8"))

    if wrapper_refs != ["v1"]:
        errors.append(
            f"{WRAPPER.relative_to(ROOT)} must contain exactly one direct testsuite "
            f"workflow reference at @v1; found {wrapper_refs!r}"
        )

    wrapper_test_refs = TEST_REF.findall(WRAPPER.read_text(encoding="utf-8"))
    if wrapper_test_refs != ["v1"]:
        errors.append(
            f"{WRAPPER.relative_to(ROOT)} must pass exactly one test_ref: v1; "
            f"found {wrapper_test_refs!r}"
        )

    for workflow in sorted(WORKFLOW_DIR.glob("*.y*ml")):
        if workflow == WRAPPER:
            continue
        refs = WORKFLOW_REF.findall(workflow.read_text(encoding="utf-8"))
        if refs:
            errors.append(
                f"{workflow.relative_to(ROOT)} calls testsuite e2e directly; "
                "call the local run-testsuite wrapper instead"
            )

    if errors:
        print("Testsuite workflow contract failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Testsuite workflow contract passed: canonical wrapper uses @v1 with test_ref: v1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
