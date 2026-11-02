"""Fast regression checks; never invoke Nix or access upstream services."""

import importlib.util
import io
import json
import os
import tempfile
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

        # x86_64 hosts are nixbot's: not evaluated or built on GitHub.
        result, calls = self.run_scope(["hosts/fnuc/default.nix"], command)
        self.assertEqual(json.loads(result)["hosts"], {"aarch64": []})
        self.assertEqual(calls.call_count, 2)

    def test_host_only_builds_aarch64_hosts(self):
        def command(*args):
            self.assertEqual(args[:2], ("nix", "eval"))
            if "builtins.attrNames" in args:
                return '["fnuc", "pica4"]'
            self.assertIn("nixosConfigurations.pica4.", args[-1])
            return (
                "aarch64-linux"
                if args[-1].endswith(".system")
                else "/nix/store/system.drv"
            )

        result, calls = self.run_scope(["hosts/pica4/default.nix"], command)
        self.assertEqual(json.loads(result)["hosts"], {"aarch64": ["pica4"]})
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


class DerivationCacheTests(unittest.TestCase):
    attribute = "nixosConfigurations.fnuc.config.system.build.toplevel.drvPath"
    drv = "/nix/store/" + "a" * 32 + "-system.drv"

    def test_cache_is_reused_only_for_exact_commit_and_target(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"CI_DRV_CACHE": directory, "CI_HEAD_SHA": "head"}),
            patch.object(scope, "output", return_value=self.drv) as command,
        ):
            self.assertEqual(scope.evaluate_drv(self.attribute), self.drv)
            self.assertEqual(scope.evaluate_drv(self.attribute), self.drv)
            self.assertEqual(command.call_count, 1)
            scope.evaluate_drv(self.attribute, revision="different")
            scope.evaluate_drv(self.attribute.replace("fnuc", "rofl-10"))
            self.assertEqual(command.call_count, 3)

    def test_corrupt_cache_is_reevaluated(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"CI_DRV_CACHE": directory, "CI_HEAD_SHA": "head"}),
            patch.object(scope, "output", return_value=self.drv) as command,
        ):
            scope.evaluate_drv(self.attribute)
            next(Path(directory).glob("*.json")).write_text("broken")
            self.assertEqual(scope.evaluate_drv(self.attribute), self.drv)
            self.assertEqual(command.call_count, 2)

    def test_old_revisions_are_pruned(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"CI_DRV_CACHE": directory, "CI_HEAD_SHA": "head"}),
        ):
            for revision in ["base", "head", "old"]:
                (Path(directory) / f"{revision}.json").write_text(
                    json.dumps({"revision": revision})
                )
            scope.prune_cache("base")
            self.assertEqual(
                sorted(p.name for p in Path(directory).iterdir()),
                ["base.json", "head.json"],
            )

    def test_failed_evaluations_are_not_cached(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"CI_DRV_CACHE": directory, "CI_HEAD_SHA": "head"}),
            patch.object(
                scope, "output", side_effect=RuntimeError("evaluation failed")
            ),
        ):
            with self.assertRaises(RuntimeError):
                scope.evaluate_drv(self.attribute)
            self.assertEqual(list(Path(directory).iterdir()), [])


class ReportTests(unittest.TestCase):
    def test_impact_summary_highlights_kernels_and_counts_hosts(self):
        old = {
            "packages": [{"name": "foo", "scope": "system", "version": "1"}],
            "kernel": {"version": "6", "modDirVersion": "6"},
            "containers": {},
        }
        new = {
            "packages": [{"name": "foo", "scope": "system", "version": "2"}],
            "kernel": {"version": "7", "modDirVersion": "7"},
            "containers": {},
        }
        other = {
            **new,
            "packages": new["packages"]
            + [{"name": "bar", "scope": "system", "version": "1"}],
        }
        targets = ["nixos:a", "nixos:b", "nixos:c"]
        result = impact.render(
            "base",
            "head",
            targets,
            {"nixos:a": (old, new), "nixos:b": (old, other), "nixos:c": (old, old)},
            {},
            80,
            "",
        )
        summary = result.split("<details>")[0]
        self.assertIn("**Kernel changes**", summary)
        self.assertIn("Kernel: 6 → 7</code> (2 configurations)", summary)
        self.assertIn("~ foo: 1 → 2</code> (2 configurations)", summary)
        self.assertIn("+ bar 1</code> (<code>nixos:b</code>)", summary)
        self.assertIn("2 changed · 1 unchanged · 0 failed", summary)
        self.assertIn("### Details by configuration", result)
        self.assertNotIn("—", result)
        self.assertIn("*Covers package names/versions", result)
        self.assertIn("transitive dependencies are not shown.*", result)

    def test_impact_summary_bounds_output_and_escapes_markup(self):
        groups = {(f"~ pkg{number}<x>: 1 → 2",): ["nixos:a"] for number in range(20)}
        summary = "\n".join(impact.summarize_changes(groups))
        self.assertIn("&lt;x&gt;", summary)
        self.assertIn("5 more distinct changes", summary)
        self.assertEqual(summary.count("<code>"), 30)

    def test_oversized_impact_report_keeps_summary(self):
        before = {
            "packages": [],
            "kernel": {"version": "6", "modDirVersion": "6"},
            "containers": {},
        }
        after = {
            "packages": [
                {"scope": "system", "name": f"pkg-{i}-" + "x" * 800, "version": "1"}
                for i in range(100)
            ],
            "kernel": {"version": "7", "modDirVersion": "7"},
            "containers": {},
        }
        report = impact.render(
            "base",
            "head",
            ["nixos:a"],
            {"nixos:a": (before, after)},
            {},
            100,
            "https://example.org/run",
        )
        self.assertIn("### TL;DR", report)
        self.assertIn("Kernel: 6 → 7", report)
        self.assertIn("Report exceeds the comment limit", report)
        self.assertLess(len(report.encode()), 58000)

    def test_impact_summary_without_changes_does_not_hide_failures(self):
        snapshot = {"packages": [], "kernel": None, "containers": {}}
        report = impact.render(
            "base",
            "head",
            ["nixos:a", "nixos:b"],
            {"nixos:a": (snapshot, snapshot)},
            {"nixos:b": ["head"]},
            80,
            "",
        )
        self.assertIn(
            "No detected changes in successfully evaluated configurations", report
        )
        self.assertIn("`nixos:b`: head evaluation failed", report)

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
