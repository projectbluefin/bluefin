import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

EXPECTED_COSIGN_SHA256 = (
    "ae1ecd212663f3693ad9edf8b1a183900c9a52d3155ba6e354237f9a0f6463fc"
)


class JustfileCosignVerificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.content = JUSTFILE.read_text(encoding="utf-8")

    def test_cosign_download_has_pinned_sha256(self) -> None:
        """verify-container must pin the expected cosign v3.1.1 SHA-256."""
        match = re.search(r'COSIGN_SHA256="([0-9a-f]{64})"', self.content)
        self.assertIsNotNone(match, "COSIGN_SHA256 definition not found in Justfile")
        assert match is not None
        self.assertEqual(
            match.group(1),
            EXPECTED_COSIGN_SHA256,
            "COSIGN_SHA256 does not match official cosign v3.1.1 linux-amd64 checksum",
        )

    def test_cosign_checksum_verified_before_install(self) -> None:
        """sha256sum verification must occur before install -m 0755."""
        self.assertIn("verify-container", self.content)
        recipe_part = self.content.split("verify-container container=")[1].split(
            "secureboot", 1
        )[0]

        sha_pos = recipe_part.find("sha256sum -c -")
        install_pos = recipe_part.find("install -m 0755")

        self.assertNotEqual(
            sha_pos, -1, "sha256sum check not found in verify-container"
        )
        self.assertNotEqual(
            install_pos, -1, "install command not found in verify-container"
        )
        self.assertLess(
            sha_pos,
            install_pos,
            "sha256sum check must execute before install command",
        )


if __name__ == "__main__":
    unittest.main()
