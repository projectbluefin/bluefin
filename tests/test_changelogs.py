#!/usr/bin/env python3
"""Unit tests for the pure parts of .github/changelogs.py."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).parent.parent / ".github" / "changelogs.py"
SPEC = importlib.util.spec_from_file_location("bluefin_changelogs", MODULE_PATH)
changelogs = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(changelogs)


class ChangelogTests(unittest.TestCase):
    def test_get_images_builds_expected_matrix(self):
        images = list(changelogs.get_images("stable"))

        self.assertEqual(len(images), 2)
        self.assertEqual({image[0] for image in images}, {"bluefin", "bluefin-nvidia-open"})

    def test_get_tags_uses_tags_shared_by_all_manifests(self):
        manifests = {
            "bluefin": {"RepoTags": ["stable-44001", "stable-44002", "stable-44003"]},
            "bluefin-nvidia-open": {
                "RepoTags": ["stable-44001", "stable-44002", "stable-44003", "stable-44003.0"]
            },
        }

        self.assertEqual(changelogs.get_tags("stable", manifests), ("stable-44002", "stable-44003"))

    def test_parse_sbom_packages_keeps_rpm_and_prefers_epoch(self):
        sbom = {
            "artifacts": [
                {"type": "rpm", "name": "bash", "version": "5.2-1.fc44"},
                {"type": "rpm", "name": "bash", "version": "1:5.2-2.fc44"},
                {"type": "deb", "name": "ignored", "version": "1.0"},
            ]
        }

        self.assertEqual(
            changelogs.parse_sbom_packages(sbom),
            {"bash": "1:5.2-2.fc44"},
        )

    def test_get_versions_strips_epoch_and_fedora_suffix(self):
        packages = {"bluefin": {"bash": "1:5.2-2.fc44", "vim": "9.1.fc44"}}

        self.assertEqual(
            changelogs.get_versions(packages),
            {"bash": "5.2-2", "vim": "9.1"},
        )

    def test_calculate_changes_reports_added_changed_and_removed_packages(self):
        changes = changelogs.calculate_changes(
            ["added", "changed", "removed"],
            {"changed": "1.0", "removed": "2.0"},
            {"added": "3.0", "changed": "1.1"},
        )

        self.assertIn("| ✨ | added | | 3.0 |", changes)
        self.assertIn("| 🔄 | changed | 1.0 | 1.1 |", changes)
        self.assertIn("| ❌ | removed | 2.0 | |", changes)

    def test_calculate_changes_omits_blacklisted_packages(self):
        changes = changelogs.calculate_changes(
            ["kernel", "bash"],
            {"kernel": "1.0", "bash": "1.0"},
            {"kernel": "2.0", "bash": "1.1"},
        )

        self.assertNotIn("kernel", changes)
        self.assertIn("bash", changes)

    @patch.object(changelogs.subprocess, "run")
    def test_get_commits_filters_merge_and_chore_commits(self, run):
        run.return_value = subprocess.CompletedProcess(
            args=["git"],
            returncode=0,
            stdout=(
                "abc123|abc|Alice|feat: keep this\n"
                "def456|def|Bob|Merge branch\n"
                "ghi789|ghi|Cara|chore: skip this\n"
            ).encode(),
        )
        manifests = {"bluefin": {"Labels": {"org.opencontainers.image.revision": "new"}}}
        previous = {"bluefin": {"Labels": {"org.opencontainers.image.revision": "old"}}}

        result = changelogs.get_commits(previous, manifests, ".")

        self.assertIn("feat: keep this", result)
        self.assertNotIn("Merge branch", result)
        self.assertNotIn("chore: skip this", result)


if __name__ == "__main__":
    unittest.main()
