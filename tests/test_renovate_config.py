import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class RenovateConfigTests(unittest.TestCase):
    def test_repository_has_one_canonical_config(self) -> None:
        candidates = [
            ROOT / "renovate.json",
            ROOT / "renovate.jsonc",
            ROOT / "renovate.json5",
            ROOT / ".github" / "renovate.json",
            ROOT / ".github" / "renovate.jsonc",
            ROOT / ".github" / "renovate.json5",
        ]
        existing = [path.relative_to(ROOT).as_posix() for path in candidates if path.exists()]
        self.assertEqual(existing, [".github/renovate.json5"])

    def test_validation_watches_canonical_config(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "validate-renovate.yml").read_text(encoding="utf-8")
        self.assertIn('      - ".github/renovate.json5"', workflow)
        self.assertNotIn('      - ".github/workflows/renovate.yml"', workflow)


if __name__ == "__main__":
    unittest.main()
