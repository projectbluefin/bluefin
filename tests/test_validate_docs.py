"""Tests for the agent-documentation contract validator.

``.github/scripts/validate-docs.py`` runs all of its checks at import time
against a ``ROOT`` derived from its own location, so the behavioural tests
below copy the script into a synthetic repository tree and run it as a
subprocess. The pure helpers (front-matter parsing, link resolution) are
imported once from a copy planted in a known-good fixture repository.
"""

from __future__ import annotations

import atexit
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = REPO_ROOT / ".github" / "scripts" / "validate-docs.py"

VALID_FRONT_MATTER = """\
---
name: {name}
version: "1.0"
last_updated: 2026-08-07
id: {name}
one_line_purpose: Do one useful thing.
entry_point: docs/skills/{name}/SKILL.md
category: ci-ops
mcp_compliance_level: partial
optimization_status: draft
status: active
dependencies: []
tags: [ci, docs]
description: >-
  A short description that stays well inside the length budget enforced by
  the documentation contract.
metadata:
  type: runbook
  source-of-truth:
    - .github/workflows/
---

# {name}
"""


def plant_repo(root: Path) -> None:
    """Create a minimal, contract-clean repository tree under ``root``."""
    scripts = root / ".github" / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy(VALIDATOR, scripts / "validate-docs.py")
    (root / "AGENTS.md").write_text("# Agents\n")
    (root / "docs" / "skills").mkdir(parents=True)
    (root / "docs" / "skills" / "index.md").write_text("# Skill index\n")


def add_skill(root: Path, name: str, front_matter: str | None = None) -> Path:
    """Write ``docs/skills/<name>/SKILL.md`` and register it in the index."""
    directory = root / "docs" / "skills" / name
    directory.mkdir(parents=True, exist_ok=True)
    skill = directory / "SKILL.md"
    skill.write_text(
        VALID_FRONT_MATTER.format(name=name) if front_matter is None else front_matter
    )
    index = root / "docs" / "skills" / "index.md"
    index.write_text(f"{index.read_text()}| {name} | [{name}]({name}/SKILL.md) |\n")
    return skill


def run_validator(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(root / ".github" / "scripts" / "validate-docs.py")],
        capture_output=True,
        text=True,
        check=False,
    )


def load_helpers() -> object:
    """Import the validator from a clean fixture so module-level checks pass."""
    fixture = tempfile.TemporaryDirectory()
    atexit.register(fixture.cleanup)
    root = Path(fixture.name)
    plant_repo(root)
    add_skill(root, "ci")
    path = root / ".github" / "scripts" / "validate-docs.py"
    spec = importlib.util.spec_from_file_location("validate_docs", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate_docs = load_helpers()


class ValidatorFixture(unittest.TestCase):
    """Base class giving each test a throwaway repository tree."""

    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.root = Path(self._temporary.name)
        plant_repo(self.root)

    def assertPasses(self) -> subprocess.CompletedProcess[str]:
        result = run_validator(self.root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def assertFailsWith(self, fragment: str) -> str:
        result = run_validator(self.root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(fragment, result.stdout)
        return result.stdout


class SuccessPathTests(ValidatorFixture):
    def test_clean_tree_passes_and_reports_counts(self) -> None:
        add_skill(self.root, "ci")
        add_skill(self.root, "build")
        result = self.assertPasses()
        self.assertIn("documentation ok: 2 skills", result.stdout)

    def test_empty_skills_directory_passes(self) -> None:
        result = self.assertPasses()
        self.assertIn("documentation ok: 0 skills", result.stdout)

    def test_dot_directories_are_not_treated_as_skills(self) -> None:
        (self.root / "docs" / "skills" / ".cache").mkdir()
        result = self.assertPasses()
        self.assertIn("documentation ok: 0 skills", result.stdout)


class LineBudgetTests(ValidatorFixture):
    def test_oversized_agents_md_is_reported(self) -> None:
        (self.root / "AGENTS.md").write_text("line\n" * 151)
        self.assertFailsWith("AGENTS.md exceeds 150 lines")

    def test_agents_md_at_the_limit_passes(self) -> None:
        (self.root / "AGENTS.md").write_text("line\n" * 150)
        self.assertPasses()

    def test_oversized_index_is_reported(self) -> None:
        index = self.root / "docs" / "skills" / "index.md"
        index.write_text("line\n" * 81)
        self.assertFailsWith("docs/skills/index.md exceeds 80 lines")

    def test_oversized_skill_is_reported(self) -> None:
        skill = add_skill(self.root, "ci")
        skill.write_text(skill.read_text() + "filler\n" * 200)
        self.assertFailsWith("docs/skills/ci/SKILL.md exceeds 180 lines")


class SkillStructureTests(ValidatorFixture):
    def test_directory_without_skill_md_is_reported(self) -> None:
        (self.root / "docs" / "skills" / "ci").mkdir()
        self.assertFailsWith("missing SKILL.md: docs/skills/ci/SKILL.md")

    def test_skill_without_front_matter_is_reported(self) -> None:
        add_skill(self.root, "ci", front_matter="# CI\n\nNo front matter here.\n")
        self.assertFailsWith("missing front matter: docs/skills/ci/SKILL.md")

    def test_skill_absent_from_index_is_reported(self) -> None:
        directory = self.root / "docs" / "skills" / "ci"
        directory.mkdir()
        (directory / "SKILL.md").write_text(VALID_FRONT_MATTER.format(name="ci"))
        self.assertFailsWith("skill missing from index: ci/SKILL.md")


class FrontMatterFieldTests(ValidatorFixture):
    def add_broken_skill(self, name: str, old: str, new: str) -> None:
        add_skill(
            self.root,
            name,
            front_matter=VALID_FRONT_MATTER.format(name=name).replace(old, new, 1),
        )

    def test_missing_required_key_is_reported(self) -> None:
        self.add_broken_skill("ci", 'version: "1.0"\n', "")
        self.assertFailsWith("missing version metadata: docs/skills/ci/SKILL.md")

    def test_name_must_match_directory(self) -> None:
        self.add_broken_skill("ci", "name: ci\n", "name: other\n")
        self.assertFailsWith("name does not match directory")

    def test_id_must_match_directory(self) -> None:
        self.add_broken_skill("ci", "id: ci\n", "id: other\n")
        self.assertFailsWith("id does not match directory")

    def test_entry_point_must_match_directory(self) -> None:
        self.add_broken_skill(
            "ci", "entry_point: docs/skills/ci/SKILL.md", "entry_point: docs/ci.md"
        )
        self.assertFailsWith("entry_point must be docs/skills/ci/SKILL.md")

    def test_invalid_category_is_reported(self) -> None:
        self.add_broken_skill("ci", "category: ci-ops", "category: nonsense")
        self.assertFailsWith("invalid category 'nonsense'")

    def test_invalid_status_is_reported(self) -> None:
        self.add_broken_skill("ci", "status: active", "status: retired")
        self.assertFailsWith("invalid status 'retired'")

    def test_missing_metadata_type_is_reported(self) -> None:
        self.add_broken_skill("ci", "  type: runbook\n", "")
        self.assertFailsWith("missing metadata.type")

    def test_invalid_metadata_type_is_reported(self) -> None:
        self.add_broken_skill("ci", "  type: runbook", "  type: essay")
        self.assertFailsWith("invalid metadata.type 'essay'")

    def test_overlong_description_is_reported(self) -> None:
        long_text = "word " * 60
        self.add_broken_skill(
            "ci",
            "  A short description that stays well inside the length budget enforced by\n"
            "  the documentation contract.\n",
            f"  {long_text.strip()}\n",
        )
        self.assertFailsWith("description exceeds 256 characters")

    def test_overlong_one_line_purpose_is_reported(self) -> None:
        self.add_broken_skill(
            "ci",
            "one_line_purpose: Do one useful thing.",
            f"one_line_purpose: {'x' * 121}",
        )
        self.assertFailsWith("one_line_purpose exceeds 120 characters")

    def test_every_error_is_printed_not_just_the_first(self) -> None:
        self.add_broken_skill("ci", "category: ci-ops", "category: nonsense")
        (self.root / "AGENTS.md").write_text("line\n" * 200)
        output = self.assertFailsWith("invalid category 'nonsense'")
        self.assertIn("AGENTS.md exceeds 150 lines", output)


class LinkCheckTests(ValidatorFixture):
    def write_markdown(self, name: str, body: str) -> None:
        (self.root / name).write_text(body)

    def test_broken_relative_link_is_reported(self) -> None:
        self.write_markdown("README.md", "See [gone](docs/missing.md).\n")
        self.assertFailsWith("broken link: README.md -> docs/missing.md")

    def test_resolvable_relative_link_passes(self) -> None:
        self.write_markdown("README.md", "See [agents](AGENTS.md).\n")
        self.assertPasses()

    def test_image_links_are_checked(self) -> None:
        self.write_markdown("README.md", "![shot](img/missing.png)\n")
        self.assertFailsWith("broken link: README.md -> img/missing.png")

    def test_external_and_anchor_links_are_ignored(self) -> None:
        self.write_markdown(
            "README.md",
            textwrap.dedent(
                """\
                [web](https://example.com/nope)
                [insecure](http://example.com/nope)
                [mail](mailto:someone@example.com)
                [anchor](#section)
                """
            ),
        )
        self.assertPasses()

    def test_fragment_is_stripped_before_resolution(self) -> None:
        self.write_markdown("README.md", "[agents](AGENTS.md#rules)\n")
        self.assertPasses()

    def test_git_directory_is_excluded_from_the_link_scan(self) -> None:
        git_dir = self.root / ".git"
        git_dir.mkdir()
        (git_dir / "NOTES.md").write_text("[gone](nowhere.md)\n")
        self.assertPasses()

    def test_undecodable_markdown_does_not_crash_the_scan(self) -> None:
        (self.root / "BINARY.md").write_bytes(b"\xff\xfe [ok](AGENTS.md)\n")
        self.assertPasses()


class ParseFrontMatterTests(unittest.TestCase):
    def parse(self, text: str) -> dict[str, str]:
        return validate_docs.parse_front_matter(textwrap.dedent(text))

    def test_scalar_values_are_unquoted(self) -> None:
        fields = self.parse(
            """\
            name: ci
            version: "1.0"
            last_updated: '2026-08-07'
            """
        )
        self.assertEqual(fields, {"name": "ci", "version": "1.0", "last_updated": "2026-08-07"})

    def test_folded_block_is_joined_onto_one_line(self) -> None:
        fields = self.parse(
            """\
            description: >-
              first line
              second line
            status: active
            """
        )
        self.assertEqual(fields["description"], "first line second line")
        self.assertEqual(fields["status"], "active")

    def test_folded_block_at_end_of_document_is_flushed(self) -> None:
        fields = self.parse(
            """\
            description: >-
              trailing block
            """
        )
        self.assertEqual(fields["description"], "trailing block")

    def test_inline_list_is_kept_verbatim(self) -> None:
        fields = self.parse("tags: [ci, docs]\n")
        self.assertEqual(fields["tags"], "[ci, docs]")

    def test_comments_and_blank_lines_are_skipped(self) -> None:
        fields = self.parse(
            """\
            # a comment
            name: ci

            status: active
            """
        )
        self.assertEqual(fields, {"name": "ci", "status": "active"})

    def test_nested_metadata_is_flattened(self) -> None:
        fields = self.parse(
            """\
            metadata:
              type: runbook
              owner: "platform"
            status: active
            """
        )
        self.assertEqual(fields["metadata.type"], "runbook")
        self.assertEqual(fields["metadata.owner"], "platform")
        self.assertEqual(fields["status"], "active")
        self.assertNotIn("metadata", fields)

    def test_deeply_nested_metadata_entries_are_ignored(self) -> None:
        fields = self.parse(
            """\
            metadata:
              type: runbook
              source-of-truth:
                - .github/workflows/
            """
        )
        self.assertEqual(fields["metadata.type"], "runbook")
        self.assertNotIn("metadata.- .github/workflows/", fields)

    def test_lines_without_a_colon_are_ignored(self) -> None:
        self.assertEqual(self.parse("just some prose\nname: ci\n"), {"name": "ci"})


class ParseNestedTests(unittest.TestCase):
    def test_only_the_requested_block_is_returned(self) -> None:
        text = textwrap.dedent(
            """\
            metadata:
              type: runbook
            other:
              type: ignored
            """
        )
        self.assertEqual(
            validate_docs.parse_nested(text, "metadata"), {"metadata.type": "runbook"}
        )

    def test_valueless_keys_are_skipped(self) -> None:
        text = "metadata:\n  type:\n  owner: platform\n"
        self.assertEqual(
            validate_docs.parse_nested(text, "metadata"), {"metadata.owner": "platform"}
        )


class LocalTargetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = Path("/repo/docs/README.md")

    def test_relative_target_resolves_against_the_source_directory(self) -> None:
        self.assertEqual(
            validate_docs.local_target(self.source, "../AGENTS.md"),
            Path("/repo/AGENTS.md"),
        )

    def test_query_string_and_fragment_are_stripped(self) -> None:
        self.assertEqual(
            validate_docs.local_target(self.source, "build.md?raw=1"),
            Path("/repo/docs/build.md"),
        )
        self.assertEqual(
            validate_docs.local_target(self.source, "build.md#step"),
            Path("/repo/docs/build.md"),
        )

    def test_angle_bracket_wrapping_is_stripped(self) -> None:
        self.assertEqual(
            validate_docs.local_target(self.source, "<build.md>"),
            Path("/repo/docs/build.md"),
        )

    def test_external_schemes_and_anchors_return_none(self) -> None:
        for target in (
            "https://example.com",
            "http://example.com",
            "mailto:a@example.com",
            "#anchor",
            "",
        ):
            with self.subTest(target=target):
                self.assertIsNone(validate_docs.local_target(self.source, target))


if __name__ == "__main__":
    unittest.main()
