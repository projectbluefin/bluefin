#!/usr/bin/env python3
"""Validate the repository's agent-documentation contract."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / "docs" / "skills"
MAX_LINES = {
    ROOT / "AGENTS.md": 120,
    SKILLS / "index.md": 80,
}
SKILL_MAX_LINES = 180
REFERENCE_MAX_LINES = 400
REQUIRED_SKILL_SECTIONS = (
    "When to Use",
    "When NOT to Use",
    "Core Process",
    "Verification",
)
FORBIDDEN_DOC_PATHS = (
    "docs/SKILL.md",
    "docs/build.md",
    "docs/ci.md",
    "docs/pr-checklist.md",
)
errors: list[str] = []


def error(message: str) -> None:
    errors.append(message)


for required in (ROOT / "AGENTS.md", SKILLS / "index.md"):
    if not required.exists():
        error(f"missing required entry point: {required.relative_to(ROOT)}")

for relative in FORBIDDEN_DOC_PATHS:
    if (ROOT / relative).exists():
        error(f"obsolete compatibility pointer must be removed: {relative}")


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
        if not re.search(r"^name:\s*[^\s].*$", front_matter, re.MULTILINE):
            error(f"missing name metadata: {skill.relative_to(ROOT)}")
        if not re.search(r"^description:\s*[^\s].*$", front_matter, re.MULTILINE):
            error(f"missing description metadata: {skill.relative_to(ROOT)}")
        if not re.search(rf"^name:\s*{re.escape(directory.name)}\s*$", front_matter, re.MULTILINE):
            error(f"name does not match directory: {skill.relative_to(ROOT)}")
    if not re.search(r"^metadata:\s*$", text, re.MULTILINE) or not re.search(
        r"^\s+source-of-truth:\s*$", text, re.MULTILINE
    ):
        error(f"missing source-of-truth metadata: {skill.relative_to(ROOT)}")
    headings = set(re.findall(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    for required_heading in REQUIRED_SKILL_SECTIONS:
        if required_heading not in headings:
            error(f"missing section '{required_heading}': {skill.relative_to(ROOT)}")
    if len(text.splitlines()) > SKILL_MAX_LINES:
        error(f"{skill.relative_to(ROOT)} exceeds {SKILL_MAX_LINES} lines")

for reference in SKILLS.glob("*/references/*.md"):
    if len(reference.read_text().splitlines()) > REFERENCE_MAX_LINES:
        error(f"{reference.relative_to(ROOT)} exceeds {REFERENCE_MAX_LINES} lines")

index = SKILLS / "index.md"
index_text = index.read_text() if index.exists() else ""
for skill in skill_files:
    expected = f"{skill.parent.name}/SKILL.md"
    if not re.search(rf"\]\({re.escape(expected)}(?:#[^)]*)?\)", index_text):
        error(f"skill missing from index: {expected}")

for flat_skill in SKILLS.glob("*.md"):
    if flat_skill.name != "index.md":
        error(f"flat skill file is not allowed: {flat_skill.relative_to(ROOT)}")

markdown_files = [
    path
    for path in ROOT.rglob("*.md")
    if ".git" not in path.parts
    and ".worktrees" not in path.parts
    and ".pytest_cache" not in path.parts
]
for source in markdown_files:
    text = source.read_text(errors="replace")
    for forbidden in FORBIDDEN_DOC_PATHS:
        if forbidden in text:
            error(f"reference to obsolete documentation path: {source.relative_to(ROOT)} -> {forbidden}")
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
