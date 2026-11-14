#!/usr/bin/env python3
import os
from pathlib import Path
import runpy
import tempfile
import unittest

relocate = runpy.run_path(str(Path(__file__).with_name("relocate-termuxpp.py")))["relocate"]


class RelocationTest(unittest.TestCase):
    def test_paths_modes_binary_and_upgrade_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "launcher"
            script.write_text("#!/data/data/com.termux/files/usr/bin/sh\n")
            script.chmod(0o555)
            binary = root / "binary"
            payload = b"\x7fELF\0/data/data/com.termux/files/usr"
            binary.write_bytes(payload)
            link = root / "link"
            link.symlink_to("/data/data/com.termux/files/home/test")
            external = root / "external"
            external.symlink_to("/nonexistent")
            config = root / "home/.config/nixpp/config.toml"
            config.parent.mkdir(parents=True)
            config.write_text('flake = "github:example/config#termux-native-test-bundle"\n')
            relocate(root)
            self.assertEqual(script.read_text(), "#!/data/data/dev.pschmitt.termux/files/usr/bin/sh\n")
            self.assertEqual(script.stat().st_mode & 0o777, 0o555)
            self.assertEqual(binary.read_bytes(), payload)
            self.assertEqual(os.readlink(link), "/data/data/dev.pschmitt.termux/files/home/test")
            self.assertEqual(os.readlink(external), "/nonexistent")
            self.assertIn("termuxpp-native-test-bundle", config.read_text())
            relocate(root)
            self.assertEqual(binary.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
