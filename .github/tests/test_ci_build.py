"""Exercise the CI shell entrypoints with Nix and niks3 publication mocked."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = r"""
source .github/workflows/scripts/ci-build.sh
nix() {
  printf '%s\n' "$*" >> "$NIX_TEST_LOG"
  if [[ "$1" == path-info ]]
  then
    printf '%s\n' /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-example
  else
    return 0
  fi
}
publish_ref() {
  printf 'published %s\n' "$1" >> "$NIX_TEST_LOG"
}
if [[ "$NIX_TEST_ACTION" == copy ]]
then
  copy_refs "" '.#test'
else
  build_ref '.#test'
fi
"""


class CiBuildTests(unittest.TestCase):
    def run_script(self, action="build"):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "commands"
            env = {
                **os.environ,
                "NIX_TEST_LOG": str(log),
                "NIX_TEST_ACTION": action,
                "NIKS3_S3_STORE": "s3://fixture",
                "NIKS3_SERVER_URL": "https://fixture",
                "NIX_CACHE_SCOPE": "main",
            }
            subprocess.run(
                ["bash", "-c", SCRIPT],
                cwd=ROOT,
                env=env,
                check=True,
                capture_output=True,
            )
            return log.read_text().splitlines()

    def test_matrix_preserves_existing_nix_configuration(self):
        script = r"""nix() {
  if [[ "$NIX_CONFIG" != $'accept-flake-config = true\nconnect-timeout = 7' ]]
  then
    return 87
  fi
  if [[ "$*" == *nixosConfigurations* ]]
  then
    printf '%s\n' '{}'
  else
    printf '%s\n' '[]'
  fi
}
source .github/workflows/scripts/nix-gh-build-matrix.sh
"""
        subprocess.run(
            ["bash", "-c", script],
            cwd=ROOT,
            check=True,
            capture_output=True,
            env={**os.environ, "NIX_CONFIG": "connect-timeout = 7"},
        )

    def test_build_always_builds(self):
        calls = self.run_script()
        self.assertTrue(any(c.startswith("build ") for c in calls))

    def test_copy_publishes_without_building(self):
        calls = self.run_script(action="copy")
        self.assertIn("published .#test", calls)
        self.assertFalse(any(c.startswith(("build ", "copy ")) for c in calls))


if __name__ == "__main__":
    unittest.main()
