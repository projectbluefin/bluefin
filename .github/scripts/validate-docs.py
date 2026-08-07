#!/usr/bin/env python3
"""Validate the repository's agent-documentation contract."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / "docs" / "skills"
MAX_LINES = {ROOT / "AGENTS.md": 150, SKILLS / "index.md": 80}
REQUIRED_KEYS = (
    "name",
    "version",
    "last_updated",
    "id",
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
CATEGORIES = {"ci-ops", "test-authoring", "meta"}
STATUSES = {"active", "deprecated", "reserved"}
DOC_TYPES = {"procedure", "reference", "runbook", "policy"}
errors: list[str] = []


def error(message: str) -> None:
    errors.append(message)


def parse_front_matter(text: str) -> dict[str, str]:
    """Read the small YAML subset used by SKILL.md front matter.

    Handles top-level scalars, folded ``>-`` blocks, inline ``[a, b]`` lists,
    and a single nested ``metadata`` mapping (exposed as ``metadata.<key>``).
    Kept dependency-free so the validate job needs no extra packages.
    """
    parsed: dict[str, str] = {}
    key: str | None = None
    folded: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))
        if key is not None and (indent > 0 or not stripped):
            if stripped:
                folded.append(stripped)
            continue
        if key is not None:
            parsed[key] = " ".join(folded)
            key, folded = None, []
        if not stripped or stripped.startswith("#") or indent > 0 or ":" not in stripped:
            continue
        name, _, value = stripped.partition(":")
        name, value = name.strip(), value.strip()
        if value in (">-", ">", "|", "|-", ""):
            if name == "metadata":
                parsed.update(parse_nested(text, name))
                continue
            key, folded = name, []
            continue
        parsed[name] = value.strip("\"'")
    if key is not None:
        parsed[key] = " ".join(folded)
    return parsed


def parse_nested(text: str, block: str) -> dict[str, str]:
    """Return ``<block>.<key>`` scalars from a nested two-space mapping."""
    parsed: dict[str, str] = {}
    inside = False
    for line in text.splitlines():
        if not line.startswith(" ") and line.strip():
            inside = line.strip().rstrip(":") == block and line.strip().endswith(":")
            continue
        if not inside or not line.startswith("  ") or line.startswith("    "):
            continue
        name, _, value = line.strip().partition(":")
        if value.strip():
            parsed[f"{block}.{name.strip()}"] = value.strip().strip("\"'")
    return parsed


def local_target(source: Path, target: str) -> Path | None:
    target = target.split("#", 1)[0].split("?", 1)[0].strip("<>")
    if not target or target.startswith(("http://", "https://", "mailto:", "#")):
        return None
    return (source.parent / target).resolve()


for path, limit in MAX_LINES.items():
    if path.exists() and len(path.read_text().splitlines()) > limit:
        error(f"{path.relative_to(ROOT)} exceeds {limit} lines")

skill_dirs = sorted(
    path for path in SKILLS.iterdir() if path.is_dir() and not path.name.startswith(".")
)
skill_files = []
for directory in skill_dirs:
    skill = directory / "SKILL.md"
    if not skill.exists():
        error(f"missing SKILL.md: {skill.relative_to(ROOT)}")
        continue
    skill_files.append(skill)
    text = skill.read_text()
    if not text.startswith("---\n"):
        error(f"missing front matter: {skill.relative_to(ROOT)}")
    else:
        front_matter = text.split("---\n", 2)[1]
        name = skill.relative_to(ROOT)
        fields = parse_front_matter(front_matter)
        for required in REQUIRED_KEYS:
            if not fields.get(required):
                error(f"missing {required} metadata: {name}")
        if fields.get("name") and fields["name"] != directory.name:
            error(f"name does not match directory: {name}")
        if fields.get("id") and fields["id"] != directory.name:
            error(f"id does not match directory: {name}")
        expected_entry = f"docs/skills/{directory.name}/SKILL.md"
        if fields.get("entry_point") and fields["entry_point"] != expected_entry:
            error(f"entry_point must be {expected_entry}: {name}")
        if fields.get("category") and fields["category"] not in CATEGORIES:
            error(f"invalid category '{fields['category']}': {name}")
        if fields.get("status") and fields["status"] not in STATUSES:
            error(f"invalid status '{fields['status']}': {name}")
        doc_type = fields.get("metadata.type")
        if not doc_type:
            error(f"missing metadata.type: {name}")
        elif doc_type not in DOC_TYPES:
            error(f"invalid metadata.type '{doc_type}': {name}")
        if len(fields.get("description", "")) > 256:
            error(f"description exceeds 256 characters: {name}")
        if len(fields.get("one_line_purpose", "")) > 120:
            error(f"one_line_purpose exceeds 120 characters: {name}")
    if len(text.splitlines()) > 180:
        error(f"{skill.relative_to(ROOT)} exceeds 180 lines")

index = SKILLS / "index.md"
index_text = index.read_text() if index.exists() else ""
for skill in skill_files:
    expected = f"{skill.parent.name}/SKILL.md"
    if expected not in index_text:
        error(f"skill missing from index: {expected}")

EXCLUDED_DIRS = {".git", ".worktrees", ".pytest_cache"}
markdown_files = [
    path
    for path in ROOT.rglob("*.md")
    if not EXCLUDED_DIRS & set(path.relative_to(ROOT).parts)
]
link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
for source in markdown_files:
    for target in link_pattern.findall(source.read_text(errors="replace")):
        resolved = local_target(source, target)
        if resolved is not None and not resolved.exists():
            error(f"broken link: {source.relative_to(ROOT)} -> {target}")

if errors:
    print("\n".join(f"ERROR: {message}" for message in errors))
    sys.exit(1)

print(f"documentation ok: {len(skill_files)} skills, {len(markdown_files)} Markdown files")
