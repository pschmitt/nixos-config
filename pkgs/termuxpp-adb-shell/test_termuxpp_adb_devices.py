import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import termuxpp_adb_devices as devices  # noqa: E402


class DeviceResolutionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "devices.json"
        self.credentials = self.root / "credentials"

    def write(self, aliases, mode=0o600):
        self.config.write_text(json.dumps({"version": 1, "devices": aliases}))
        self.config.chmod(mode)

    def resolve(self, name, listing):
        return devices.resolve_device(name, self.config, lambda: listing, self.credentials)

    def test_raw_serial_needs_no_config_or_adb(self):
        with mock.patch.object(devices, "DEFAULT_CONFIG", self.root / "missing.json"):
            device = devices.resolve_device("RAW", adb_devices=mock.Mock(side_effect=AssertionError),
                                            credential_root=self.credentials)
        self.assertEqual(device.serial, "RAW")
        self.assertIsNone(device.alias)
        self.assertEqual(device.credential_dir.parent, self.credentials)

    def test_alias_resolves_exact_prefix_and_metadata_candidates(self):
        self.write({"one": {"serials": ["USB1", "192.0.2.1:5555"]}, "two": {"serial_prefixes": ["adb-X-"]},
                    "three": {"metadata": {"model": ["M3"]}}})
        listing = [("USB1", "device", {}), ("adb-X-abc._tcp", "device", {}), ("other", "device", {"model": "M3"})]
        self.assertEqual(self.resolve("one", listing).serial, "USB1")
        self.assertEqual(self.resolve("two", listing).serial, "adb-X-abc._tcp")
        self.assertEqual(self.resolve("three", listing).serial, "other")

    def test_ambiguous_missing_and_unready_are_errors(self):
        self.write({"one": {"serials": ["USB1", "192.0.2.1:5555"]}})
        with self.assertRaisesRegex(RuntimeError, "ambiguous"):
            self.resolve("one", [("USB1", "device"), ("192.0.2.1:5555", "device")])
        with self.assertRaisesRegex(RuntimeError, "no ready device.*USB1 \\(unauthorized\\)"):
            self.resolve("one", [("USB1", "unauthorized")])
        with self.assertRaisesRegex(RuntimeError, "matches no connected"):
            self.resolve("one", [("unrelated", "device")])
        # A second transport that is not ready does not make the ready one ambiguous.
        self.assertEqual(self.resolve("one", [("USB1", "device"), ("192.0.2.1:5555", "offline")]).serial, "USB1")

    def test_credentials_are_stable_reused_and_never_copied(self):
        self.write({"one": {"serials": ["USB1", "WIFI1"]}})
        listing = [("USB1", "device")]
        stable = self.credentials / "aliases" / "one"
        self.assertEqual(self.resolve("one", listing).credential_dir, stable)
        legacy = devices.credential_dir_for("USB1", None, self.credentials)
        legacy.mkdir(parents=True)
        (legacy / "client.key").write_text("existing")
        self.assertEqual(self.resolve("one", listing).credential_dir, legacy)
        self.assertEqual((legacy / "client.key").read_text(), "existing")
        self.assertFalse(stable.exists())
        stable.mkdir(parents=True)
        (stable / "client.key").write_text("alias")
        self.assertEqual(self.resolve("one", listing).credential_dir, stable)

    def test_legacy_credentials_of_another_listed_serial_are_reused_uniquely(self):
        self.write({"one": {"serials": ["USB1", "WIFI1"]}})
        wifi = devices.credential_dir_for("WIFI1", None, self.credentials)
        wifi.mkdir(parents=True)
        (wifi / "client.key").write_text("existing")
        device = self.resolve("one", [("USB1", "device")])
        self.assertEqual((device.serial, device.credential_dir, device.credential_error), ("USB1", wifi, None))
        usb = devices.credential_dir_for("USB1", None, self.credentials)
        usb.mkdir(parents=True)
        (usb / "client.key").write_text("other")
        device = self.resolve("one", [("USB1", "device")])
        self.assertIn("several of its serials", device.credential_error)
        self.assertEqual(device.serial, "USB1")
        self.assertEqual((wifi / "client.key").read_text(), "existing")
        self.write({"one": {"serials": ["USB1", "WIFI1"], "credential_dir": str(wifi)}})
        device = self.resolve("one", [("USB1", "device")])
        self.assertEqual((device.credential_dir, device.credential_error), (wifi, None))

    def test_model_metadata_selects_device_without_serials(self):
        self.write({"one": {"metadata": {"model": ["MODEL1"]}}})
        listing = [("a:5555", "device", {"model": "OTHER"}), ("b", "device", {"model": "MODEL1"})]
        self.assertEqual(self.resolve("one", listing).serial, "b")
        with self.assertRaisesRegex(RuntimeError, "ambiguous"):
            self.resolve("one", listing + [("c:5555", "device", {"model": "MODEL1"})])

    def test_explicit_credential_dir_wins(self):
        target = self.root / "explicit"
        self.write({"one": {"serials": ["USB1"], "credential_dir": str(target)}})
        self.assertEqual(self.resolve("one", [("USB1", "device")]).credential_dir, target)

    def test_ssh_settings_default_and_validate(self):
        self.write({"one": {"serials": ["USB1"]},
                    "two": {"serials": ["USB2"], "ssh": {"port": 2200, "start_argv": ["sh", "-c", "true"]}}})
        aliases = devices.load_aliases(self.config)
        self.assertEqual(aliases["one"].ssh_port, 2222)
        self.assertEqual(aliases["one"].ssh_start_argv, ())
        self.assertEqual(aliases["two"].ssh_start_argv, ("sh", "-c", "true"))
        for bad in ({"serials": []}, {"serials": ["a"], "extra": 1}, {"serials": ["a b"]},
                    {"serials": ["a"], "ssh": {"port": 0}}, {"serials": ["a"], "ssh": {"port": True}},
                    {"serials": ["a"], "ssh": {"start_argv": ["-x"]}}, {"serials": ["a"], "credential_dir": "rel"},
                    {"metadata": {"serial": ["a"]}}):
            self.write({"bad": bad})
            with self.assertRaises(RuntimeError, msg=bad):
                devices.load_aliases(self.config)
        self.write({"bad name": {"serials": ["a"]}})
        with self.assertRaises(RuntimeError):
            devices.load_aliases(self.config)

    def test_config_must_not_be_writable_by_others_or_missing_when_explicit(self):
        self.write({"one": {"serials": ["USB1"]}}, mode=0o666)
        with self.assertRaisesRegex(RuntimeError, "not writable by others"):
            devices.load_aliases(self.config)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            devices.load_aliases(self.root / "missing.json")
        self.config.write_text("{not json")
        self.config.chmod(0o600)
        with self.assertRaisesRegex(RuntimeError, "not valid JSON"):
            devices.load_aliases(self.config)

    def test_environment_selects_config_and_default_missing_means_no_aliases(self):
        self.write({"one": {"serials": ["USB1"]}})
        with mock.patch.dict(os.environ, {devices.CONFIG_ENV: str(self.config)}):
            self.assertEqual(list(devices.load_aliases()), ["one"])
        with mock.patch.dict(os.environ, {}, clear=False), mock.patch.object(devices, "DEFAULT_CONFIG", self.root / "none"):
            os.environ.pop(devices.CONFIG_ENV, None)
            self.assertEqual(devices.load_aliases(), {})

    @mock.patch.object(devices.subprocess, "run")
    def test_adb_devices_parser(self, run):
        run.return_value = mock.Mock(returncode=0, stdout=(
            "List of devices attached\n* daemon started\nUSB1\tdevice usb:1-2 product:p model:M_1 device:d transport_id:3\n"
            "192.0.2.1:5555\toffline\n\n"))
        self.assertEqual(devices.list_adb_devices(), [
            ("USB1", "device", {"usb": "1-2", "product": "p", "model": "M_1", "device": "d", "transport_id": "3"}),
            ("192.0.2.1:5555", "offline", {})])
        run.side_effect = subprocess.TimeoutExpired("adb", 1)
        with self.assertRaises(RuntimeError):
            devices.list_adb_devices()


if __name__ == "__main__":
    unittest.main()
