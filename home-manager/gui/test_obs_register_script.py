import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "register", Path(__file__).with_name("obs-register-script.py")
)
register = importlib.util.module_from_spec(spec)
spec.loader.exec_module(register)


COLLECTION = {
    "name": "Zoom",
    "current_scene": "ARD",
    "sources": [{"name": "Browser", "settings": {"url": "https://example.invalid/x?token=abc"}}],
    "scene_order": [{"name": "ARD"}],
    "modules": {
        "scripts-tool": [
            {"path": "/scripts/bounce.lua", "settings": {"a": 1, "b": [1.5, "x"]}},
            {"path": "/scripts/timetracking.lua", "settings": {}},
        ],
        "other-module": {"keep": True},
    },
}


class RegisterTests(unittest.TestCase):
    trailing = ""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.config = root / "obs-studio"
        (self.config / "basic" / "scenes").mkdir(parents=True)
        (self.config / "scripts").mkdir()
        self.script = self.config / "scripts" / "obs-broadcast-audio.lua"
        self.script.write_text("-- lua\n")
        (self.config / "user.ini").write_text(
            "[General]\nSceneCollectionFile=Wrong.json\n"
            "[Basic]\nSceneCollection=Zoom\nSceneCollectionFile=Zoom.json\n"
        )
        self.collection = self.config / "basic" / "scenes" / "Zoom.json"
        self.proc = root / "proc"
        self.proc.mkdir()
        self.write(COLLECTION)
        self.collection.chmod(0o644)

    def write(self, data):
        self.collection.write_text(json.dumps(data, indent=4) + self.trailing)

    def load(self):
        return json.loads(self.collection.read_text())

    def run_register(self, **kwargs):
        return register.register(self.config, self.script, proc=self.proc, **kwargs)

    def fake_obs(self, comm=".obs-wrapped"):
        process = self.proc / "123"
        process.mkdir()
        (process / "comm").write_text(comm + "\n")

    def test_registers_and_preserves_everything(self):
        self.assertEqual(self.run_register(), 0)
        data = self.load()
        expected = copy.deepcopy(COLLECTION)
        expected["modules"]["scripts-tool"].append({"path": str(self.script), "settings": {}})
        self.assertEqual(data, expected)
        self.assertEqual(stat.S_IMODE(self.collection.stat().st_mode), 0o644)
        backup = Path(f"{self.collection}.obs-register.bak")
        self.assertEqual(json.loads(backup.read_text()), COLLECTION)
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)
        leftovers = [p.name for p in self.collection.parent.iterdir() if p.name.startswith(".")]
        self.assertEqual(leftovers, [])

    def test_keeps_trailing_newline_convention(self):
        self.trailing = "\n"
        self.write(COLLECTION)
        self.run_register()
        self.assertTrue(self.collection.read_bytes().endswith(b"}\n"))
        self.trailing = ""
        self.write(COLLECTION)
        Path(f"{self.collection}.obs-register.bak").unlink()
        self.run_register()
        self.assertTrue(self.collection.read_bytes().endswith(b"}"))

    def test_idempotent(self):
        self.assertEqual(self.run_register(), 0)
        first = self.collection.read_bytes()
        mtime = self.collection.stat().st_mtime_ns
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(self.collection.read_bytes(), first)
        self.assertEqual(self.collection.stat().st_mtime_ns, mtime)
        self.assertEqual(len(self.load()["modules"]["scripts-tool"]), 3)

    def test_symlinked_registration_counts_as_registered(self):
        target = Path(self.tmp.name) / "store.lua"
        target.write_text("-- lua\n")
        link = self.config / "scripts" / "alias.lua"
        link.symlink_to(target)
        self.script.unlink()
        self.script.symlink_to(target)
        data = copy.deepcopy(COLLECTION)
        data["modules"]["scripts-tool"].append({"path": str(link), "settings": {"x": 1}})
        self.write(data)
        before = self.collection.read_bytes()
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(self.collection.read_bytes(), before)

    def test_defers_while_obs_runs(self):
        self.fake_obs()
        before = self.collection.read_bytes()
        self.assertEqual(self.run_register(), register.EX_TEMPFAIL)
        self.assertEqual(self.collection.read_bytes(), before)
        self.assertFalse(Path(f"{self.collection}.obs-register.bak").exists())

    def test_other_process_is_not_obs(self):
        self.fake_obs("obs-browser-pag")
        self.assertEqual(self.run_register(), 0)

    def test_already_registered_while_running_is_fine(self):
        self.assertEqual(self.run_register(), 0)
        self.fake_obs()
        self.assertEqual(self.run_register(), 0)

    def test_check_never_writes(self):
        before = self.collection.read_bytes()
        self.assertEqual(self.run_register(check=True), 3)
        self.assertEqual(self.collection.read_bytes(), before)
        self.run_register()
        self.assertEqual(self.run_register(check=True), 0)

    def test_creates_missing_modules(self):
        self.write({"name": "Zoom", "sources": []})
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(
            self.load()["modules"]["scripts-tool"],
            [{"path": str(self.script), "settings": {}}],
        )

    def test_invalid_json_is_an_error_and_untouched(self):
        self.collection.write_text("{broken")
        with self.assertRaises(register.RegistrationError):
            self.run_register()
        self.assertEqual(self.collection.read_text(), "{broken")

    def test_unexpected_layout_is_an_error(self):
        data = copy.deepcopy(COLLECTION)
        data["modules"]["scripts-tool"] = {"oops": 1}
        self.write(data)
        with self.assertRaises(register.RegistrationError):
            self.run_register()
        self.assertEqual(self.load(), data)

    def test_stale_registration_is_repointed_keeping_settings(self):
        data = copy.deepcopy(COLLECTION)
        data["modules"]["scripts-tool"].append(
            {"path": "/gone/store/obs-broadcast-audio.lua", "settings": {"keep": 1}}
        )
        self.write(data)
        self.assertEqual(self.run_register(), 0)
        scripts = self.load()["modules"]["scripts-tool"]
        self.assertEqual(len(scripts), 3)
        self.assertEqual(scripts[2], {"path": str(self.script), "settings": {"keep": 1}})

    def test_same_name_elsewhere_is_left_alone(self):
        other = Path(self.tmp.name) / "elsewhere"
        other.mkdir()
        (other / "obs-broadcast-audio.lua").write_text("-- other\n")
        data = copy.deepcopy(COLLECTION)
        data["modules"]["scripts-tool"].append(
            {"path": str(other / "obs-broadcast-audio.lua"), "settings": {}}
        )
        self.write(data)
        before = self.collection.read_bytes()
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(self.collection.read_bytes(), before)

    def test_missing_script_or_collection_is_a_noop(self):
        self.script.unlink()
        before = self.collection.read_bytes()
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(self.collection.read_bytes(), before)
        self.script.write_text("-- lua\n")
        self.collection.unlink()
        self.assertEqual(self.run_register(), 0)

    def test_falls_back_to_global_ini_and_rejects_unsafe_names(self):
        (self.config / "user.ini").unlink()
        (self.config / "global.ini").write_text("[Basic]\nSceneCollectionFile=Zoom\n")
        self.assertEqual(self.run_register(), 0)
        self.assertEqual(len(self.load()["modules"]["scripts-tool"]), 3)
        (self.config / "global.ini").write_text("[Basic]\nSceneCollectionFile=../x\n")
        with self.assertRaises(register.RegistrationError):
            self.run_register()

    def test_changed_while_processing_is_deferred(self):
        original = json.dumps
        racing_text = original(COLLECTION) + " "

        def racing(*args, **kwargs):
            self.collection.write_text(racing_text)
            return original(*args, **kwargs)

        with patch.object(register.json, "dumps", racing):
            self.assertEqual(self.run_register(), register.EX_TEMPFAIL)
        self.assertEqual(len(self.load()["modules"]["scripts-tool"]), 2)

    def test_output_has_no_scene_data(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.run_register()
            self.collection.write_text("{broken")
            self.assertEqual(
                register.main(["--config-dir", str(self.config)]), 1
            )
        text = out.getvalue() + err.getvalue()
        for secret in ("token=abc", "bounce", "Zoom"):
            self.assertNotIn(secret, text)

    def test_obs_running_matches_only_own_uid(self):
        self.fake_obs()
        self.assertTrue(register.obs_running(self.proc))
        with patch.object(os, "getuid", return_value=os.getuid() + 1):
            self.assertFalse(register.obs_running(self.proc))


if __name__ == "__main__":
    unittest.main()
