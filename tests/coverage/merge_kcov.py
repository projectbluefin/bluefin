#!/usr/bin/env python3
"""Merge kcov reports from BATS child shells into source-mapped reports."""

from __future__ import annotations

import argparse
import html
import time
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


def _is_shell_source(path: Path) -> bool:
    try:
        with path.open(encoding="utf-8") as source_file:
            first_line = source_file.readline().lstrip()
    except (OSError, UnicodeDecodeError):
        return False
    return path.suffix == ".sh" or (
        first_line.startswith("#!") and "bash" in first_line
    )


def _source_path(
    filename: str, report: Path, repo_root: Path, allowed_roots: tuple[Path, ...]
) -> Path | None:
    mapping_file = report.parent.parent / "source-path"
    if mapping_file.is_file():
        candidate = Path(mapping_file.read_text(encoding="utf-8").strip())
    else:
        candidate = Path(filename)
        if not candidate.is_absolute():
            candidate = repo_root / candidate

    candidate = candidate.resolve()
    if not candidate.is_file() or not _is_shell_source(candidate):
        return None
    if not any(candidate.is_relative_to(root) for root in allowed_roots):
        return None
    return candidate


def _collect_coverage(raw_dir: Path, repo_root: Path) -> dict[Path, dict[int, int]]:
    allowed_roots = (
        (repo_root / "build_files").resolve(),
        (repo_root / "system_files").resolve(),
    )
    coverage: dict[Path, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    seen_reports: set[Path] = set()
    reports = []

    for report in sorted(raw_dir.rglob("cobertura.xml")):
        resolved_report = report.resolve()
        if resolved_report in seen_reports:
            continue
        seen_reports.add(resolved_report)
        reports.append(report)

    reports.sort(
        key=lambda report: (
            (report.parent.parent / "source-path").is_file(),
            str(report),
        )
    )
    for report in reports:
        is_child_report = (report.parent.parent / "source-path").is_file()
        root = ET.parse(report).getroot()
        for class_element in root.findall("./packages/package/classes/class"):
            source = _source_path(
                class_element.get("filename", ""),
                report,
                repo_root,
                allowed_roots,
            )
            if source is None:
                continue
            relative_source = source.relative_to(repo_root)
            for line in class_element.findall("./lines/line"):
                number = int(line.get("number", "0"))
                hits = int(float(line.get("hits", "0")))
                if is_child_report and (
                    relative_source not in coverage
                    or number not in coverage[relative_source]
                ):
                    continue
                coverage[relative_source][number] += hits

    return coverage


def _write_cobertura(
    coverage: dict[Path, dict[int, int]], output_dir: Path, repo_root: Path
) -> tuple[int, int]:
    total_lines = sum(len(lines) for lines in coverage.values())
    covered_lines = sum(
        1 for lines in coverage.values() for hits in lines.values() if hits > 0
    )
    line_rate = covered_lines / total_lines if total_lines else 0

    root = ET.Element(
        "coverage",
        {
            "line-rate": f"{line_rate:.6f}",
            "lines-covered": str(covered_lines),
            "lines-valid": str(total_lines),
            "branch-rate": "0",
            "branches-covered": "0",
            "branches-valid": "0",
            "complexity": "0",
            "version": "bluefin-kcov",
            "timestamp": str(int(time.time())),
        },
    )
    sources = ET.SubElement(root, "sources")
    ET.SubElement(sources, "source").text = str(repo_root)
    packages = ET.SubElement(root, "packages")
    package = ET.SubElement(
        packages,
        "package",
        {
            "name": "bluefin-shell",
            "line-rate": f"{line_rate:.6f}",
            "branch-rate": "0",
            "complexity": "0",
        },
    )
    classes = ET.SubElement(package, "classes")

    for source, lines in sorted(coverage.items(), key=lambda item: str(item[0])):
        file_covered = sum(1 for hits in lines.values() if hits > 0)
        file_rate = file_covered / len(lines) if lines else 0
        class_element = ET.SubElement(
            classes,
            "class",
            {
                "name": str(source).replace("/", "."),
                "filename": str(source),
                "line-rate": f"{file_rate:.6f}",
                "branch-rate": "0",
                "complexity": "0",
            },
        )
        class_lines = ET.SubElement(class_element, "lines")
        for number, hits in sorted(lines.items()):
            ET.SubElement(
                class_lines,
                "line",
                {"number": str(number), "hits": str(hits), "branch": "false"},
            )

    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    tree.write(output_dir / "cobertura.xml", encoding="utf-8", xml_declaration=True)
    return covered_lines, total_lines


def _write_html(
    coverage: dict[Path, dict[int, int]],
    output_dir: Path,
    repo_root: Path,
    covered_lines: int,
    total_lines: int,
) -> None:
    total_rate = 100 * covered_lines / total_lines if total_lines else 0
    rows = []
    details = []

    for index, (source, hits_by_line) in enumerate(
        sorted(coverage.items(), key=lambda item: str(item[0]))
    ):
        file_covered = sum(1 for hits in hits_by_line.values() if hits > 0)
        file_total = len(hits_by_line)
        file_rate = 100 * file_covered / file_total if file_total else 0
        anchor = f"source-{index}"
        rows.append(
            "<tr>"
            f'<td><a href="#{anchor}">{html.escape(str(source))}</a></td>'
            f"<td>{file_covered}</td><td>{file_total}</td>"
            f"<td>{file_rate:.1f}%</td></tr>"
        )

        source_lines = (repo_root / source).read_text(encoding="utf-8").splitlines()
        rendered_lines = []
        for number, text in enumerate(source_lines, start=1):
            hits = hits_by_line.get(number)
            css_class = "neutral"
            marker = " "
            if hits is not None:
                css_class = "covered" if hits > 0 else "missed"
                marker = str(hits)
            rendered_lines.append(
                f'<span class="{css_class}">'
                f"{number:4} {marker:>4} {html.escape(text)}</span>"
            )
        details.append(
            f'<section id="{anchor}"><h2>{html.escape(str(source))}</h2>'
            f"<p>{file_covered} / {file_total} lines ({file_rate:.1f}%)</p>"
            f"<pre>{chr(10).join(rendered_lines)}</pre></section>"
        )

    document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Bluefin BATS coverage</title>
<style>
body {{ color: #1f2328; font-family: sans-serif; margin: 2rem; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #d0d7de; padding: .4rem .6rem; text-align: left; }}
th {{ background: #f6f8fa; }}
pre {{ background: #f6f8fa; overflow-x: auto; padding: 1rem; }}
pre span {{ display: block; }}
.covered {{ background: #dafbe1; }}
.missed {{ background: #ffebe9; }}
.neutral {{ color: #656d76; }}
</style>
</head>
<body>
<h1>Bluefin BATS coverage</h1>
<p><strong>{covered_lines} / {total_lines} lines ({total_rate:.1f}%)</strong></p>
<table>
<thead><tr><th>File</th><th>Covered</th><th>Valid</th><th>Coverage</th></tr></thead>
<tbody>{''.join(rows)}</tbody>
</table>
{''.join(details)}
</body>
</html>
"""
    (output_dir / "index.html").write_text(document, encoding="utf-8")

    summary_lines = [
        "## BATS shell coverage",
        "",
        f"**{covered_lines} / {total_lines} lines ({total_rate:.1f}%)**",
        "",
        "| File | Covered | Valid | Coverage |",
        "|---|---:|---:|---:|",
    ]
    for source, lines in sorted(coverage.items(), key=lambda item: str(item[0])):
        file_covered = sum(1 for hits in lines.values() if hits > 0)
        file_rate = 100 * file_covered / len(lines) if lines else 0
        summary_lines.append(
            f"| `{source}` | {file_covered} | {len(lines)} | {file_rate:.1f}% |"
        )
    (output_dir / "summary.md").write_text(
        "\n".join(summary_lines) + "\n", encoding="utf-8"
    )


def generate_report(raw_dir: Path, output_dir: Path, repo_root: Path) -> tuple[int, int]:
    repo_root = repo_root.resolve()
    coverage = _collect_coverage(raw_dir.resolve(), repo_root)
    if not coverage:
        raise RuntimeError("No shell source files were found in kcov reports")

    output_dir.mkdir(parents=True, exist_ok=True)
    covered_lines, total_lines = _write_cobertura(
        coverage, output_dir, repo_root
    )
    if covered_lines == 0:
        raise RuntimeError("kcov collected no executed shell source lines")
    _write_html(coverage, output_dir, repo_root, covered_lines, total_lines)
    return covered_lines, total_lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    covered, total = generate_report(args.raw_dir, args.output_dir, args.repo_root)
    print(f"BATS shell coverage: {covered}/{total} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
