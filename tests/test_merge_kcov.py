"""Tests for the BATS kcov report merger."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


MODULE_PATH = Path(__file__).parent / "coverage" / "merge_kcov.py"
SPEC = importlib.util.spec_from_file_location("merge_kcov", MODULE_PATH)
assert SPEC and SPEC.loader
merge_kcov = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(merge_kcov)


def write_report(path: Path, filename: str, lines: dict[int, int]) -> None:
    root = ET.Element("coverage")
    packages = ET.SubElement(root, "packages")
    package = ET.SubElement(packages, "package")
    classes = ET.SubElement(package, "classes")
    class_element = ET.SubElement(classes, "class", {"filename": filename})
    class_lines = ET.SubElement(class_element, "lines")
    for number, hits in lines.items():
        ET.SubElement(
            class_lines,
            "line",
            {"number": str(number), "hits": str(hits)},
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


class MergeKcovTests(unittest.TestCase):
    def test_merges_sandbox_hits_into_original_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repo = root / "repo"
            source = repo / "build_files" / "example.sh"
            source.parent.mkdir(parents=True)
            source.write_text(
                "#!/usr/bin/bash\nfirst=true\nsecond=false\n", encoding="utf-8"
            )

            raw = root / "raw"
            write_report(
                raw / "top" / "bats" / "cobertura.xml",
                "build_files/example.sh",
                {2: 0, 3: 0},
            )
            child = raw / "run.123"
            (child / "source-path").parent.mkdir(parents=True, exist_ok=True)
            (child / "source-path").write_text(str(source), encoding="utf-8")
            write_report(
                child / "bash" / "cobertura.xml",
                "/repo/tests/unit/.bats-sandbox/example.sh",
                {2: 3, 3: 0, 4: 99},
            )

            output = root / "output"
            covered, total = merge_kcov.generate_report(raw, output, repo)

            self.assertEqual((covered, total), (1, 2))
            report = ET.parse(output / "cobertura.xml")
            class_element = report.find("./packages/package/classes/class")
            self.assertIsNotNone(class_element)
            assert class_element is not None
            self.assertEqual(class_element.get("filename"), "build_files/example.sh")
            hits = {
                int(line.get("number", "0")): int(line.get("hits", "0"))
                for line in class_element.findall("./lines/line")
            }
            self.assertEqual(hits, {2: 3, 3: 0})
            self.assertIn("50.0%", (output / "index.html").read_text(encoding="utf-8"))

    def test_rejects_zero_coverage_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repo = root / "repo"
            source = repo / "system_files" / "example.sh"
            source.parent.mkdir(parents=True)
            source.write_text("#!/usr/bin/bash\nexit 0\n", encoding="utf-8")
            raw = root / "raw"
            write_report(
                raw / "top" / "bats" / "cobertura.xml",
                "system_files/example.sh",
                {2: 0},
            )

            with self.assertRaisesRegex(RuntimeError, "no executed"):
                merge_kcov.generate_report(raw, root / "output", repo)


if __name__ == "__main__":
    unittest.main()
