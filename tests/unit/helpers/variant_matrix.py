"""Derive the published image-variant set from the Justfile.

The `Justfile` declares the variant axes (`images`, `flavors`, `tags`) and the
`image_name` recipe turns an (image, flavor) pair into a published image name.
Everything else in the repo that names a published image — the release matrix,
the promotion matrix, the vulnerability-scan matrix, the testing-build flavor
list — is a restatement of that derivation. This module performs the
derivation once so `image_variant_matrix_test.bats` can hold the restatements
to it.

Nothing in the build path imports this module; it exists only for the gate.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
JUSTFILE = REPO_ROOT / "Justfile"
WORKFLOWS = REPO_ROOT / ".github" / "workflows"


def _assoc_array(name: str, text: str) -> list[str]:
    """Return the keys of a bash associative-array literal in the Justfile.

    Matches `name := '(\\n    [key]=value\\n)'`.
    """
    match = re.search(rf"^{name} := '\((.*?)\)'", text, re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"Justfile no longer declares a `{name}` map")
    keys = re.findall(r"\[([^\]]+)\]=", match.group(1))
    if not keys:
        raise AssertionError(f"Justfile `{name}` map is empty")
    return keys


def images() -> list[str]:
    return _assoc_array("images", JUSTFILE.read_text())


def flavors() -> list[str]:
    return _assoc_array("flavors", JUSTFILE.read_text())


def image_name(image: str, flavor: str) -> str:
    """Mirror of the Justfile `image_name` recipe.

    `image_name` publishes the bare image name for the `main` flavor and
    `<image>-<flavor>` for every other flavor. `assert_image_name_rule()`
    guards this mirror against the recipe drifting away from it.
    """
    return image if flavor == "main" else f"{image}-{flavor}"


def variants() -> set[str]:
    """Every image name this repo publishes, derived from the Justfile axes."""
    return {
        image_name(image, flavor) for image in images() for flavor in flavors()
    }


def assert_image_name_rule() -> None:
    """Fail if the Justfile `image_name` recipe stops matching `image_name()`.

    The recipe is shell inside a `just` recipe body, so it cannot be executed
    here without `just`. Instead, pin its two branches textually: any edit to
    the naming rule must also update this module and the expectations that
    depend on it.
    """
    text = JUSTFILE.read_text()
    match = re.search(
        r"^image_name image=.*?\n(.*?)(?=\n# )", text, re.MULTILINE | re.DOTALL
    )
    if match is None:
        raise AssertionError("Justfile no longer declares an `image_name` recipe")
    body = match.group(1)
    expected = [
        r'if \[\[ "\{\{ flavor \}\}" =~ main \]\]; then',
        r"image_name=\{\{ image \}\}",
        r'image_name="\{\{ image \}\}-\{\{ flavor \}\}"',
    ]
    missing = [pattern for pattern in expected if not re.search(pattern, body)]
    if missing:
        raise AssertionError(
            "Justfile `image_name` recipe no longer matches "
            f"helpers/variant_matrix.py:image_name(); missing {missing}"
        )


def workflow(name: str) -> str:
    path = WORKFLOWS / name
    if not path.is_file():
        raise AssertionError(f"missing workflow {name}")
    return path.read_text()


def json_field_values(text: str, field: str) -> set[str]:
    """Collect every `"<field>":"<value>"` occurrence in a workflow body."""
    return set(re.findall(rf'"{field}"\s*:\s*"([^"]+)"', text))


def json_literal_after(text: str, marker: str) -> object:
    """Parse the first JSON array literal appearing after `marker`."""
    index = text.find(marker)
    if index < 0:
        raise AssertionError(f"marker not found: {marker!r}")
    start = text.find("[", index)
    if start < 0:
        raise AssertionError(f"no JSON array after marker: {marker!r}")
    depth = 0
    for offset in range(start, len(text)):
        if text[offset] == "[":
            depth += 1
        elif text[offset] == "]":
            depth -= 1
            if depth == 0:
                return json.loads(text[start : offset + 1])
    raise AssertionError(f"unterminated JSON array after marker: {marker!r}")


def compare(actual: set[str], expected: set[str], site: str) -> None:
    if actual != expected:
        raise AssertionError(
            f"{site} disagrees with the Justfile variant matrix; "
            f"missing={sorted(expected - actual)} extra={sorted(actual - expected)}"
        )
