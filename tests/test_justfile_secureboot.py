import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
JUSTFILE = ROOT / "Justfile"

EXPECTED_AKMODS_COMMIT = "c30e9467fe158dcf82c5176dec76d4373871ffda"
EXPECTED_KERNEL_SIGN_SHA256 = (
    "4e5c68474cb133fd8984d9599762cece9100c3e6cd8a9709aeaabd85dd9e70d1"
)
EXPECTED_AKMODS_KEY2_SHA256 = (
    "c01ef5e7fb9f6108fc58735f7eeb4dec084764a8aac404831e0ce3f9da63757d"
)


class JustfileSecurebootTests(unittest.TestCase):
    def setUp(self) -> None:
        self.content = JUSTFILE.read_text(encoding="utf-8")
        self.assertIn("secureboot", self.content)
        # Extract the secureboot recipe section
        self.recipe = self.content.split("secureboot $image=")[1].split("fedora_version", 1)[0]

    def test_secureboot_uses_pinned_akmods_commit(self) -> None:
        """secureboot recipe must pin the akmods commit."""
        match = re.search(r'AKMODS_COMMIT="([0-9a-f]{40})"', self.recipe)
        self.assertIsNotNone(match, "AKMODS_COMMIT not found in secureboot recipe")
        assert match is not None
        self.assertEqual(match.group(1), EXPECTED_AKMODS_COMMIT)

    def test_no_mutable_main_cert_urls(self) -> None:
        """secureboot recipe must not fetch certs from mutable main branch."""
        self.assertNotIn(
            "akmods/raw/main/certs/public_key.der",
            self.recipe,
            "Found unpinned public_key.der URL tracking main",
        )
        self.assertNotIn(
            "akmods/raw/main/certs/public_key_2.der",
            self.recipe,
            "Found unpinned public_key_2.der URL tracking main",
        )

    def test_cert_checksums_verified_before_openssl(self) -> None:
        """Both certs must be verified with sha256sum before openssl conversion."""
        self.assertIn(EXPECTED_KERNEL_SIGN_SHA256, self.recipe)
        self.assertIn(EXPECTED_AKMODS_KEY2_SHA256, self.recipe)

        kernel_sha_pos = self.recipe.find(EXPECTED_KERNEL_SIGN_SHA256)
        akmods_sha_pos = self.recipe.find(EXPECTED_AKMODS_KEY2_SHA256)
        openssl_pos = self.recipe.find("openssl x509")

        self.assertNotEqual(kernel_sha_pos, -1)
        self.assertNotEqual(akmods_sha_pos, -1)
        self.assertNotEqual(openssl_pos, -1)

        self.assertLess(kernel_sha_pos, openssl_pos)
        self.assertLess(akmods_sha_pos, openssl_pos)


if __name__ == "__main__":
    unittest.main()
