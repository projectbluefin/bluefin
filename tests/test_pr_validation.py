import unittest
from pathlib import Path


WORKFLOW = Path(__file__).parents[1] / ".github" / "workflows" / "pr-validation.yml"


class PrValidationTests(unittest.TestCase):
    def test_bats_tee_pipeline_enables_pipefail_first(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        marker = "      - name: Run unit tests\n"
        self.assertIn(marker, workflow)

        step = workflow.split(marker, 1)[1].split("\n      - name: ", 1)[0]
        self.assertIn("set -o pipefail", step)
        self.assertIn("bats --formatter tap tests/unit/ | tee results.tap", step)
        self.assertLess(step.index("set -o pipefail"), step.index("| tee results.tap"))


if __name__ == "__main__":
    unittest.main()
