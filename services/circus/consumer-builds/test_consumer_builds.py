import copy
import io
import tarfile
import unittest
from unittest.mock import patch

from consumer_builds import archive_snapshot, canonical, plans, wrapper_lock


class ConsumerBuildTests(unittest.TestCase):
    def setUp(self):
        self.producer = {
            "original": {"type": "github", "owner": "example", "repo": "producer"},
            "locked": {"type": "github", "rev": "a" * 40, "__final": True},
            "locks": {
                "root": "root",
                "nodes": {
                    "root": {"inputs": {"nixpkgs": "nixpkgs", "home-manager": "hm"}},
                },
            },
        }
        self.consumer = {
            "root": "root",
            "nodes": {
                "root": {"inputs": {"demo": "demo", "nixpkgs": "nixpkgs", "home-manager": "hm"}},
                "demo": {"inputs": {"nixpkgs": ["nixpkgs"], "home-manager": ["home-manager"]}},
                "hm": {
                    "original": {"type": "github", "repo": "home-manager"},
                    "locked": {"type": "github", "rev": "b" * 40},
                    "inputs": {"nixpkgs": ["nixpkgs"]},
                },
                "nixpkgs": {
                    "original": {"type": "tarball", "url": "https://example.org/nixpkgs"},
                    "locked": {"type": "tarball", "url": "https://example.org/nixpkgs", "narHash": "sha256-abc"},
                },
            },
        }
        self.declaration = {
            "pilot": {
                "repository": "example/consumer",
                "ref": "main",
                "input": "demo",
                "follows": ["nixpkgs", "home-manager"],
                "packages": {"aarch64-linux": ["demo"]},
            },
        }

    def test_uses_consumer_lock_even_for_tarball_inputs(self):
        lock = wrapper_lock(self.producer, self.consumer, "demo", ["nixpkgs", "home-manager"])
        nodes = lock["nodes"]
        aliases = nodes["root"]["inputs"]
        hm = nodes[aliases["consumer-home-manager"]]
        nixpkgs = nodes[aliases["consumer-nixpkgs"]]
        self.assertEqual(nixpkgs["locked"], self.consumer["nodes"]["nixpkgs"]["locked"])
        self.assertEqual(hm["inputs"]["nixpkgs"], aliases["consumer-nixpkgs"])
        self.assertNotIn("__final", nodes["producer"]["locked"])

    def test_unrelated_consumer_changes_do_not_reschedule(self):
        def fingerprint(lock, consumer_sha):
            with patch("consumer_builds.read_consumer_lock", return_value=lock):
                with patch("consumer_builds.nix_json", side_effect=[self.declaration, self.producer]):
                    return next(plans("example/producer", "a" * 40, "example/consumer", consumer_sha))[2]

        expected = fingerprint(self.consumer, "1" * 40)
        updated = copy.deepcopy(self.consumer)
        updated["nodes"]["root"]["inputs"]["unrelated"] = "elsewhere"
        self.assertEqual(fingerprint(updated, "2" * 40), expected)
        updated["nodes"]["nixpkgs"]["locked"]["narHash"] = "sha256-def"
        self.assertNotEqual(fingerprint(updated, "3" * 40), expected)

    def test_snapshot_archive_is_deterministic(self):
        files = {"flake.nix": b"{}", "flake.lock": canonical({"version": 7})}
        archive = archive_snapshot(files)
        self.assertEqual(archive, archive_snapshot(dict(reversed(list(files.items())))))
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as tar:
            self.assertEqual(tar.extractfile("flake.lock").read(), files["flake.lock"])


if __name__ == "__main__":
    unittest.main()
