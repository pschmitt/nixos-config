"""Fast regression checks; never invoke Nix or access upstream services."""

import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


scope = load("scope", ".github/workflows/scripts/ci-scope.py")
notes = load("notes", "scripts/nix-update-release-notes.py")
impact = load("impact", ".github/workflows/scripts/pr-impact.py")


class ScopeTests(unittest.TestCase):
    def run_scope(self, files, command=None, classify=False):
        stdout = io.StringIO()
        with (
            patch.object(scope, "changed_files", return_value=files),
            patch.object(
                scope,
                "output",
                side_effect=command or AssertionError("Unexpected evaluation"),
            ) as calls,
            patch("sys.argv", ["ci-scope"] + (["--classify-only"] if classify else [])),
            patch("sys.stdout", stdout),
        ):
            scope.main()
        return stdout.getvalue().strip(), calls

    def test_documentation_never_evaluates(self):
        result, calls = self.run_scope(["README.md", "docs/foo.txt"])
        self.assertEqual(json.loads(result), scope.empty_matrix())
        calls.assert_not_called()

    def test_preflight_never_evaluates(self):
        for files, expected in [
            ([], "false"),
            (["README.md"], "false"),
            (["flake.lock"], "true"),
            (None, "true"),
        ]:
            with self.subTest(files=files):
                result, calls = self.run_scope(files, classify=True)
                self.assertEqual(result, expected)
                calls.assert_not_called()

    def test_host_only_does_not_evaluate_other_hosts_or_packages(self):
        def command(*args):
            self.assertEqual(args[:2], ("nix", "eval"))
            if "builtins.attrNames" in args:
                return '["fnuc", "rofl-10"]'
            self.assertIn("nixosConfigurations.fnuc.", args[-1])
            return (
                "x86_64-linux"
                if args[-1].endswith(".system")
                else "/nix/store/system.drv"
            )

        result, calls = self.run_scope(["hosts/fnuc/default.nix"], command)
        self.assertEqual(
            json.loads(result)["hosts"], {"amd64": ["fnuc"], "aarch64": []}
        )
        self.assertEqual(calls.call_count, 3)

    def test_unknown_and_shared_paths_require_builds(self):
        for path in [
            "modules/foo.nix",
            "flake.lock",
            "new-file",
            ".github/workflows/nix-build.yaml",
        ]:
            self.assertTrue(scope.needs_build(path))

    def test_reporting_and_tests_do_not_build_systems(self):
        for path in [
            ".github/tests/test_ci.py",
            ".github/workflows/nix-update.yaml",
            ".github/workflows/scripts/pr-impact.py",
        ]:
            self.assertFalse(scope.needs_build(path))


class ReportTests(unittest.TestCase):
    def test_shared_change_takes_precedence_over_host_only(self):
        targets = {"nixos:fnuc": "fnuc", "nixos:rofl-10": "rofl-10"}
        self.assertEqual(
            impact.select_targets(
                targets, ["hosts/fnuc/default.nix", "modules/a.nix"], [], False
            ),
            sorted(targets),
        )

    def test_release_notes_normalize_links_and_line_endings(self):
        result = notes.normalize_notes(
            "## Changes\r\n[Docs](docs/guide.md)",
            "owner/repo",
            "v1.2.3",
            "https://github.com/owner/repo/releases/tag/v1.2.3",
        )
        self.assertNotIn("\r", result)
        self.assertIn("https://github.com/owner/repo/blob/v1.2.3/docs/guide.md", result)

    def test_release_notes_close_unterminated_fence(self):
        result = notes.normalize_notes(
            "```sh\necho hello", "owner/repo", "v1", "https://example.org"
        )
        self.assertTrue(result.rstrip().endswith("```"))


if __name__ == "__main__":
    unittest.main()
