"""Exercise the CI shell entrypoints with Nix and SSH publication mocked."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = r"""
source .github/workflows/scripts/ci-build.sh
resolve_output_paths() {
  printf '%s\n' '["/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-example"]'
}
nix() {
  printf '%s\n' "$*" >> "$NIX_TEST_LOG"
  if [[ "$1" == path-info ]]
  then
    [[ -n "${NIX_TEST_HIT:-}" ]]
  else
    return 0
  fi
}
retain_ref() {
  printf '%s\n' retained >> "$NIX_TEST_LOG"
}
publish_s3_ref() {
  printf '%s\n' published >> "$NIX_TEST_LOG"
}
if [[ "$NIX_TEST_ACTION" == copy ]]
then
  copy_refs "" '.#test'
elif [[ "$NIX_TEST_ACTION" == check ]]
then
  main --pkg test --system x86_64-linux --check-cache
else
  build_ref '.#test'
fi
"""


class CacheHitTests(unittest.TestCase):
    def run_script(self, hit, action="build"):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "commands"
            env = {
                **os.environ,
                "NIX_TEST_LOG": str(log),
                "NIX_TEST_ACTION": action,
                "NIX_TEST_HIT": "1" if hit else "",
                "NIX_DEST_STORE_URL": "ssh://fixture",
                "NIX_CACHE_PUBLISH_HOST": "fixture",
                "NIX_CACHE_SCOPE": "main",
            }
            env.pop("NIX_STORE_PRIVKEY", None)
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

    def test_cache_hit_is_retained_without_local_build(self):
        calls = self.run_script(True)
        self.assertIn("retained", calls)
        self.assertFalse(any(c.startswith("build ") for c in calls))

    def test_cache_miss_builds_normally(self):
        calls = self.run_script(False)
        self.assertTrue(any(c.startswith("build ") for c in calls))
        self.assertNotIn("retained", calls)

    def test_preflight_hit_is_retained(self):
        calls = self.run_script(True, action="check")
        self.assertIn("retained", calls)
        self.assertFalse(any(c.startswith("build ") for c in calls))

    def test_preflight_miss_does_not_build(self):
        with self.assertRaises(subprocess.CalledProcessError) as result:
            self.run_script(False, action="check")
        self.assertEqual(result.exception.returncode, 1)

    def test_cached_copy_needs_no_local_closure_or_signing_key(self):
        calls = self.run_script(True, action="copy")
        self.assertIn("retained", calls)
        self.assertIn("published", calls)
        self.assertFalse(any(c.startswith(("copy ", "store sign ")) for c in calls))


if __name__ == "__main__":
    unittest.main()
