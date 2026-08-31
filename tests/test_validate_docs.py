"""Tests for the agent-documentation contract validator.

``.github/scripts/validate-docs.py`` derives ``ROOT`` from its own location
(``parents[2]``) and runs its checks at import time. Both facts are used here:
every test copies the real script into a synthetic repository so the checks run
against fixture data instead of the live tree.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / ".github" / "scripts" / "validate-docs.py"

SKILL_TEMPLATE = """---
name: {name}
version: "1.0"
last_updated: 2026-01-01
id: {name}
one_line_purpose: {purpose}
entry_point: docs/skills/{entry}/SKILL.md
category: {category}
mcp_compliance_level: partial
optimization_status: draft
status: {status}
dependencies: []
tags: [example]
description: >-
  {description}
metadata:
  type: {doc_type}
  source-of-truth:
    - Containerfile
---

# {name}

Body text.
"""


def build_skill(
    name: str = "example",
    *,
    entry: str | None = None,
    purpose: str = "Example skill used by the validator tests.",
    category: str = "ci-ops",
    status: str = "active",
    doc_type: str = "procedure",
    description: str = "Example skill body used to exercise the validator.",
) -> str:
    return SKILL_TEMPLATE.format(
        name=name,
        entry=entry if entry is not None else name,
        purpose=purpose,
        category=category,
        status=status,
        doc_type=doc_type,
        description=description,
    )


class SyntheticRepo:
    """A minimal, valid repository laid out the way the validator expects."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.skills = root / "docs" / "skills"
        self.skills.mkdir(parents=True)
        (root / "AGENTS.md").write_text("# Agents\n", encoding="utf-8")
        self.write_skill("example")
        self.write_index("example")
        script_target = root / ".github" / "scripts" / "validate-docs.py"
        script_target.parent.mkdir(parents=True)
        script_target.write_text(SCRIPT.read_text(encoding="utf-8"), encoding="utf-8")
        self.script = script_target

    def write_skill(self, name: str, body: str | None = None, **kwargs: object) -> Path:
        skill = self.skills / name / "SKILL.md"
        skill.parent.mkdir(parents=True, exist_ok=True)
        skill.write_text(
            body if body is not None else build_skill(name, **kwargs),  # type: ignore[arg-type]
            encoding="utf-8",
        )
        return skill

    def write_index(self, *names: str) -> None:
        lines = ["# Skills index", ""]
        lines += [f"- [{name}]({name}/SKILL.md)" for name in names]
        (self.skills / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def run(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(self.script)],
            capture_output=True,
            text=True,
            check=False,
        )


class ValidatorTestCase(unittest.TestCase):
    """Base case that provides a fresh synthetic repository per test."""

    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.repo = SyntheticRepo(Path(self._temporary.name))

    def assertFailsWith(self, fragment: str) -> str:
        result = self.repo.run()
        self.assertEqual(result.returncode, 1, msg=result.stdout + result.stderr)
        self.assertIn(fragment, result.stdout)
        return result.stdout


def load_module(script: Path):
    """Import the validator from a synthetic repo where it exits successfully."""
    spec = importlib.util.spec_from_file_location("validate_docs_under_test", script)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module


class HappyPathTests(ValidatorTestCase):
    def test_valid_repository_passes_and_reports_counts(self) -> None:
        result = self.repo.run()
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertIn("documentation ok: 1 skills", result.stdout)

    def test_hidden_directories_under_skills_are_not_treated_as_skills(self) -> None:
        (self.repo.skills / ".cache").mkdir()
        result = self.repo.run()
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertIn("documentation ok: 1 skills", result.stdout)


class LineLimitTests(ValidatorTestCase):
    def test_agents_md_over_150_lines_is_rejected(self) -> None:
        (self.repo.root / "AGENTS.md").write_text("x\n" * 151, encoding="utf-8")
        self.assertFailsWith("ERROR: AGENTS.md exceeds 150 lines")

    def test_agents_md_at_the_limit_is_accepted(self) -> None:
        (self.repo.root / "AGENTS.md").write_text("x\n" * 150, encoding="utf-8")
        self.assertEqual(self.repo.run().returncode, 0)

    def test_skills_index_over_80_lines_is_rejected(self) -> None:
        index = self.repo.skills / "index.md"
        index.write_text(index.read_text(encoding="utf-8") + "x\n" * 80, encoding="utf-8")
        self.assertFailsWith("ERROR: docs/skills/index.md exceeds 80 lines")

    def test_skill_over_180_lines_is_rejected(self) -> None:
        self.repo.write_skill("example", body=build_skill("example") + "filler\n" * 180)
        self.assertFailsWith("ERROR: docs/skills/example/SKILL.md exceeds 180 lines")


class FrontMatterContractTests(ValidatorTestCase):
    def test_missing_skill_file_is_reported(self) -> None:
        (self.repo.skills / "orphan").mkdir()
        self.assertFailsWith("ERROR: missing SKILL.md: docs/skills/orphan/SKILL.md")

    def test_missing_front_matter_is_reported(self) -> None:
        self.repo.write_skill("example", body="# example\n\nNo front matter here.\n")
        self.assertFailsWith("ERROR: missing front matter: docs/skills/example/SKILL.md")

    def test_each_required_key_is_enforced(self) -> None:
        required = (
            "version",
            "last_updated",
            "one_line_purpose",
            "entry_point",
            "category",
            "mcp_compliance_level",
            "optimization_status",
            "status",
            "dependencies",
            "tags",
            "description",
        )
        for key in required:
            with self.subTest(key=key):
                body = "\n".join(
                    line
                    for line in build_skill("example").splitlines()
                    if not line.startswith(f"{key}:")
                )
                self.repo.write_skill("example", body=body + "\n")
                self.assertFailsWith(
                    f"ERROR: missing {key} metadata: docs/skills/example/SKILL.md"
                )

    def test_name_must_match_directory(self) -> None:
        self.repo.write_skill(
            "example", body=build_skill("example").replace("name: example", "name: other", 1)
        )
        self.assertFailsWith(
            "ERROR: name does not match directory: docs/skills/example/SKILL.md"
        )

    def test_id_must_match_directory(self) -> None:
        self.repo.write_skill(
            "example", body=build_skill("example").replace("id: example", "id: other", 1)
        )
        self.assertFailsWith("ERROR: id does not match directory: docs/skills/example/SKILL.md")

    def test_entry_point_must_match_the_skill_location(self) -> None:
        self.repo.write_skill("example", entry="somewhere-else")
        self.assertFailsWith(
            "ERROR: entry_point must be docs/skills/example/SKILL.md: "
            "docs/skills/example/SKILL.md"
        )

    def test_category_must_be_known(self) -> None:
        self.repo.write_skill("example", category="not-a-category")
        self.assertFailsWith("ERROR: invalid category 'not-a-category'")

    def test_every_documented_category_is_accepted(self) -> None:
        for category in ("ci-ops", "test-authoring", "meta"):
            with self.subTest(category=category):
                self.repo.write_skill("example", category=category)
                self.assertEqual(self.repo.run().returncode, 0)

    def test_status_must_be_known(self) -> None:
        self.repo.write_skill("example", status="retired")
        self.assertFailsWith("ERROR: invalid status 'retired'")

    def test_every_documented_status_is_accepted(self) -> None:
        for status in ("active", "deprecated", "reserved"):
            with self.subTest(status=status):
                self.repo.write_skill("example", status=status)
                self.assertEqual(self.repo.run().returncode, 0)

    def test_metadata_type_is_required(self) -> None:
        body = build_skill("example").replace("  type: procedure\n", "")
        self.repo.write_skill("example", body=body)
        self.assertFailsWith("ERROR: missing metadata.type: docs/skills/example/SKILL.md")

    def test_metadata_type_must_be_known(self) -> None:
        self.repo.write_skill("example", doc_type="essay")
        self.assertFailsWith("ERROR: invalid metadata.type 'essay'")

    def test_every_documented_metadata_type_is_accepted(self) -> None:
        for doc_type in ("procedure", "reference", "runbook", "policy"):
            with self.subTest(doc_type=doc_type):
                self.repo.write_skill("example", doc_type=doc_type)
                self.assertEqual(self.repo.run().returncode, 0)

    def test_description_over_256_characters_is_rejected(self) -> None:
        self.repo.write_skill("example", description="d" * 257)
        self.assertFailsWith("ERROR: description exceeds 256 characters")

    def test_one_line_purpose_over_120_characters_is_rejected(self) -> None:
        self.repo.write_skill("example", purpose="p" * 121)
        self.assertFailsWith("ERROR: one_line_purpose exceeds 120 characters")


class IndexAndLinkTests(ValidatorTestCase):
    def test_skill_absent_from_index_is_reported(self) -> None:
        self.repo.write_skill("second")
        self.assertFailsWith("ERROR: skill missing from index: second/SKILL.md")

    def test_broken_relative_link_is_reported(self) -> None:
        (self.repo.root / "README.md").write_text(
            "See [missing](docs/nope.md).\n", encoding="utf-8"
        )
        self.assertFailsWith("ERROR: broken link: README.md -> docs/nope.md")

    def test_external_and_anchor_links_are_not_resolved(self) -> None:
        (self.repo.root / "README.md").write_text(
            textwrap.dedent(
                """\
                [web](https://example.com/nope.md)
                [insecure](http://example.com/nope.md)
                [mail](mailto:nobody@example.com)
                [anchor](#section)
                [self-anchor](AGENTS.md#section)
                """
            ),
            encoding="utf-8",
        )
        self.assertEqual(self.repo.run().returncode, 0)

    def test_git_directory_markdown_is_excluded_from_link_checks(self) -> None:
        broken = self.repo.root / ".git" / "notes.md"
        broken.parent.mkdir()
        broken.write_text("[gone](nope.md)\n", encoding="utf-8")
        self.assertEqual(self.repo.run().returncode, 0)

    def test_all_errors_are_reported_in_one_run(self) -> None:
        self.repo.write_skill("example", category="bogus", status="retired")
        output = self.assertFailsWith("ERROR: invalid category 'bogus'")
        self.assertIn("ERROR: invalid status 'retired'", output)


class ParserTests(ValidatorTestCase):
    """Unit-level coverage of the dependency-free front-matter parser."""

    def setUp(self) -> None:
        super().setUp()
        self.module = load_module(self.repo.script)

    def test_scalar_quotes_are_stripped(self) -> None:
        parsed = self.module.parse_front_matter('name: "example"\nversion: \'1.0\'\n')
        self.assertEqual(parsed, {"name": "example", "version": "1.0"})

    def test_folded_block_is_joined_onto_one_line(self) -> None:
        parsed = self.module.parse_front_matter(
            "description: >-\n  first line\n  second line\nstatus: active\n"
        )
        self.assertEqual(parsed["description"], "first line second line")
        self.assertEqual(parsed["status"], "active")

    def test_trailing_folded_block_is_flushed(self) -> None:
        parsed = self.module.parse_front_matter("description: |\n  only line\n")
        self.assertEqual(parsed["description"], "only line")

    def test_comments_and_blank_lines_are_ignored(self) -> None:
        parsed = self.module.parse_front_matter("# comment\n\nname: example\n")
        self.assertEqual(parsed, {"name": "example"})

    def test_inline_list_is_kept_verbatim(self) -> None:
        parsed = self.module.parse_front_matter("tags: [a, b]\ndependencies: []\n")
        self.assertEqual(parsed["tags"], "[a, b]")
        self.assertEqual(parsed["dependencies"], "[]")

    def test_metadata_block_is_flattened_with_a_dotted_prefix(self) -> None:
        parsed = self.module.parse_front_matter(
            "metadata:\n  type: procedure\n  source-of-truth:\n    - Containerfile\nstatus: active\n"
        )
        self.assertEqual(parsed["metadata.type"], "procedure")
        self.assertNotIn("metadata.source-of-truth", parsed)
        self.assertEqual(parsed["status"], "active")

    def test_parse_nested_ignores_other_top_level_blocks(self) -> None:
        text = "other:\n  type: ignored\nmetadata:\n  type: procedure\n"
        self.assertEqual(
            self.module.parse_nested(text, "metadata"), {"metadata.type": "procedure"}
        )

    def test_local_target_resolves_relative_to_the_source_file(self) -> None:
        source = self.repo.skills / "example" / "SKILL.md"
        resolved = self.module.local_target(source, "../index.md")
        self.assertEqual(resolved, self.repo.skills / "index.md")

    def test_local_target_strips_anchors_query_strings_and_brackets(self) -> None:
        source = self.repo.skills / "example" / "SKILL.md"
        for target in ("../index.md#top", "../index.md?v=1", "<../index.md>"):
            with self.subTest(target=target):
                self.assertEqual(
                    self.module.local_target(source, target),
                    self.repo.skills / "index.md",
                )

    def test_local_target_returns_none_for_non_local_targets(self) -> None:
        source = self.repo.skills / "example" / "SKILL.md"
        for target in ("https://example.com", "http://example.com", "mailto:a@b.c", "#top", ""):
            with self.subTest(target=target):
                self.assertIsNone(self.module.local_target(source, target))


if __name__ == "__main__":
    unittest.main()
