#!/usr/bin/env python3
"""Validate the repository's agent-documentation contract."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / "docs" / "skills"
MAX_LINES = {ROOT / "AGENTS.md": 150, SKILLS / "index.md": 80}
errors: list[str] = []


def error(message: str) -> None:
    errors.append(message)


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
    if len(text.splitlines()) > 180:
        error(f"{skill.relative_to(ROOT)} exceeds 180 lines")

index = SKILLS / "index.md"
index_text = index.read_text() if index.exists() else ""
for skill in skill_files:
    expected = f"{skill.parent.name}/SKILL.md"
    if expected not in index_text:
        error(f"skill missing from index: {expected}")

markdown_files = [
    path
    for path in ROOT.rglob("*.md")
    if ".git" not in path.parts
    and ".worktrees" not in path.parts
    and ".pytest_cache" not in path.parts
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
