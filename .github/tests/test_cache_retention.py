"""Retention tests use temporary roots and never invoke Nix."""

import importlib.util
import json
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SOURCE = (
    Path(__file__).resolve().parents[2] / "services/harmonia/scripts/cache-retain.py"
)
spec = importlib.util.spec_from_file_location("retention", SOURCE)
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        directory = Path(self.temporary.name)
        self.roots = directory / "roots"
        self.state = directory / "state"
        self.roots.mkdir()
        self.state.mkdir()
        for key, value in [("ROOTS", self.roots), ("STATE", self.state)]:
            context = patch.object(retention, key, value)
            context.start()
            self.addCleanup(context.stop)
        self.command = patch.object(retention.subprocess, "run").start()
        self.addCleanup(patch.stopall)

    def record(
        self,
        timestamp=1,
        scope="main",
        target="packages.x86_64-linux.example",
        letter="a",
    ):
        return {
            "scope": scope,
            "target": target,
            "timestamp": timestamp,
            "revision": letter * 40,
            "paths": [f"/nix/store/{letter * 32}-example"],
        }

    def root(self, record):
        return self.roots / record["scope"] / record["target"] / "0"

    def test_publish_creates_a_direct_gc_root_and_verifies_http(self):
        record = self.record()
        retention.publish(record)
        self.assertEqual(str(self.root(record).readlink()), record["paths"][0])
        verification = self.command.call_args_list[1].args[0]
        self.assertIn("http://127.0.0.1:42766", verification)
        self.assertIn("--sigs-needed", verification)
        self.assertNotIn("--no-check-sigs", verification)

    def test_newer_main_replaces_old_but_old_run_cannot_replace_new(self):
        old, new = self.record(), self.record(timestamp=2, letter="b")
        retention.publish(old)
        retention.publish(new)
        retention.publish(old)
        self.assertEqual(str(self.root(new).readlink()), new["paths"][0])
        self.assertEqual(len(list(self.root(new).parent.iterdir())), 1)

    def test_failed_verification_preserves_previous_output(self):
        old, new = self.record(), self.record(timestamp=2, letter="b")
        retention.publish(old)
        self.command.side_effect = [None, subprocess.CalledProcessError(1, "verify")]
        with self.assertRaises(subprocess.CalledProcessError):
            retention.publish(new)
        self.assertEqual(str(self.root(old).readlink()), old["paths"][0])
        self.assertFalse(list(self.root(old).parent.glob("incoming-*")))

    def test_pr_roots_expire_while_main_roots_remain(self):
        main, pr = self.record(), self.record(scope="pr-123")
        retention.publish(main)
        retention.publish(pr)
        with patch.object(retention.time, "time", return_value=time.time() + 4 * 86400):
            retention.prune()
        self.assertTrue(self.root(main).is_symlink())
        self.assertFalse(self.root(pr).is_symlink())

    def test_publication_metadata_is_group_writable(self):
        record = self.record()
        retention.publish(record)
        metadata = self.state / "main" / (record["target"] + ".json")
        self.assertEqual(metadata.stat().st_mode & 0o777, 0o664)
        self.assertEqual(json.loads(metadata.read_text())["paths"], record["paths"])

    def test_similar_target_names_have_independent_roots(self):
        first, second = self.record(target="foo"), self.record(target="foo--0")
        retention.publish(first)
        retention.publish(second)
        retention.publish(first)
        self.assertTrue(self.root(second).is_symlink())

    def test_capacity_preserves_headroom_for_missing_paths(self):
        path = self.record()["paths"][0]
        gib = 1024**3
        with (
            patch.object(
                retention.subprocess, "check_output", return_value=path + "\n"
            ),
            patch.object(
                retention.os,
                "statvfs",
                return_value=SimpleNamespace(f_bavail=20 * gib, f_frsize=1),
            ),
        ):
            self.assertFalse(retention.capacity({path: {"narSize": 6 * gib}}))

    def test_existing_outputs_can_be_rooted_even_with_low_space(self):
        path = self.record()["paths"][0]
        with (
            patch.object(retention.subprocess, "check_output", return_value=""),
            patch.object(
                retention.os,
                "statvfs",
                return_value=SimpleNamespace(f_bavail=1, f_frsize=1),
            ),
        ):
            self.assertTrue(retention.capacity({path: {"narSize": 1000}}))

    def test_reject_path_traversal(self):
        with self.assertRaises(ValueError):
            retention.publish(self.record(target="../other"))


if __name__ == "__main__":
    unittest.main()
