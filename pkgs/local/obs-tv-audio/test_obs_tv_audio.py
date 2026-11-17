"""Mock-only tests for obs-tv-audio: no OBS, no network, no audio."""

import contextlib
import importlib.util
import io
import os
import unittest
from types import SimpleNamespace as NS

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("obs_tv_audio", os.path.join(HERE, "obs-tv-audio.py"))
tv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tv)


def item(name, kind="ffmpeg_source", enabled=True, group=False):
    return {
        "sourceName": name,
        "inputKind": None if group or kind is None else kind,
        "isGroup": group or None,
        "sceneItemEnabled": enabled,
    }


class FakeObs:
    """Records every mutating call; refuses anything outside the API we expect."""

    def __init__(self, scene, scenes, inputs):
        self.scene = scene
        self.scenes = scenes
        self.inputs = inputs  # name -> {"muted": bool, "db": float}
        self.calls = []

    def get_current_program_scene(self):
        return NS(current_program_scene_name=self.scene)

    def get_scene_item_list(self, name):
        return NS(scene_items=self.scenes[name])

    get_group_scene_item_list = get_scene_item_list

    def get_input_mute(self, name):
        return NS(input_muted=self.inputs[name]["muted"])

    def get_input_volume(self, name):
        return NS(input_volume_db=self.inputs[name]["db"], input_volume_mul=1.0)

    def set_input_mute(self, name, muted):
        self.calls.append(("mute", name, muted))
        self.inputs[name]["muted"] = muted

    def set_input_volume(self, name, vol_mul=None, vol_db=None):
        assert vol_mul is None
        self.calls.append(("volume", name, vol_db))
        self.inputs[name]["db"] = vol_db


def world(scene="ARD"):
    scenes = {
        "ARD": [item("ARD Live"), item("ZDF Live", enabled=False), item("Microphone", "pulse_input_capture"), item("Desktop", "pulse_output_capture")],
        "ZDF": [item("ZDF Live"), item("ARD Live", enabled=False)],
        "Tagesschau": [item("Overlay", None), item("Group", group=True)],
        "Overlay": [item("Browser", "browser_source")],
        "Group": [item("Media", "ffmpeg_source"), item("Hidden Media", "ffmpeg_source", enabled=False)],
        "🚬 brb": [item("ARD Live"), item("Microphone", "pulse_input_capture")],
        "Other": [item("Browser", "browser_source")],
    }
    inputs = {n: {"muted": False, "db": -10.0} for n in ("ARD Live", "ZDF Live", "Browser", "Media", "Microphone", "Desktop")}
    return FakeObs(scene, scenes, inputs)


def run(argv, fake):
    out, err = io.StringIO(), io.StringIO()
    code = tv.run(tv.parser().parse_args(argv), client_factory=lambda: fake, out=out, err=err)
    return code, out.getvalue(), err.getvalue()


class TvAudioTests(unittest.TestCase):
    def test_mute_targets_only_the_active_tv_source(self):
        fake = world("ARD")
        code, _, _ = run(["mute"], fake)
        self.assertEqual(code, 0)
        self.assertEqual(fake.calls, [("mute", "ARD Live", True)])
        self.assertFalse(fake.inputs["Microphone"]["muted"])
        self.assertFalse(fake.inputs["ZDF Live"]["muted"])

    def test_mute_is_explicit_true_never_toggle_and_idempotent(self):
        fake = world("ZDF")
        fake.inputs["ZDF Live"]["muted"] = True
        code, _, _ = run(["mute"], fake)
        self.assertEqual(code, 0)
        self.assertEqual(fake.calls, [("mute", "ZDF Live", True)])
        self.assertTrue(fake.inputs["ZDF Live"]["muted"])

    def test_tagesschau_walks_nested_scenes_and_groups_visible_only(self):
        fake = world("Tagesschau")
        code, _, _ = run(["mute"], fake)
        self.assertEqual(code, 0)
        self.assertEqual({c[1] for c in fake.calls}, {"Browser", "Media"})

    def test_non_tv_scene_fails_closed_without_changes(self):
        for scene in ("🚬 brb", "Other"):
            fake = world(scene)
            for argv in (["mute"], ["volume", "up"], ["volume", "down"]):
                code, _, err = run(argv, fake)
                self.assertEqual(code, tv.EXIT_NO_SOURCE)
                self.assertIn("nothing changed", err)
            self.assertEqual(fake.calls, [])

    def test_unrelated_kind_with_allowlisted_name_is_ignored(self):
        fake = world("ARD")
        fake.scenes["ARD"] = [item("ARD Live", "pulse_input_capture")]
        code, _, _ = run(["mute"], fake)
        self.assertEqual(code, tv.EXIT_NO_SOURCE)
        self.assertEqual(fake.calls, [])

    def test_versioned_kind_suffix_is_accepted(self):
        fake = world("ARD")
        fake.scenes["ARD"] = [item("ARD Live", "ffmpeg_source_v2")]
        code, _, _ = run(["mute"], fake)
        self.assertEqual(code, 0)

    def test_volume_steps_and_never_touches_mute(self):
        fake = world("ARD")
        fake.inputs["ARD Live"]["muted"] = True
        code, _, _ = run(["volume", "up"], fake)
        self.assertEqual(code, 0)
        self.assertEqual(fake.calls, [("volume", "ARD Live", -7.0)])
        self.assertTrue(fake.inputs["ARD Live"]["muted"])
        run(["volume", "down", "--step-db", "2"], fake)
        self.assertEqual(fake.calls[-1], ("volume", "ARD Live", -9.0))
        self.assertTrue(all(c[0] == "volume" for c in fake.calls))

    def test_volume_is_clamped_at_both_ends(self):
        fake = world("ARD")
        fake.inputs["ARD Live"]["db"] = -1.0
        run(["volume", "up"], fake)
        self.assertEqual(fake.calls[-1], ("volume", "ARD Live", 0.0))
        before = len(fake.calls)
        run(["volume", "up"], fake)
        self.assertEqual(len(fake.calls), before)
        fake.inputs["ARD Live"]["db"] = -39.0
        run(["volume", "down"], fake)
        self.assertEqual(fake.calls[-1], ("volume", "ARD Live", -40.0))
        before = len(fake.calls)
        run(["volume", "down"], fake)
        self.assertEqual(len(fake.calls), before)

    def test_volume_never_boosts_or_lowers_outside_the_bounds(self):
        self.assertEqual(tv.clamp_step(6.0, "up", 3.0), 6.0)
        self.assertEqual(tv.clamp_step(6.0, "down", 3.0), 3.0)
        self.assertEqual(tv.clamp_step(-100.0, "down", 3.0), -100.0)
        self.assertEqual(tv.clamp_step(-100.0, "up", 3.0), -97.0)
        self.assertEqual(tv.clamp_step(float("-inf"), "up", 3.0), -97.0)

    def test_step_is_bounded(self):
        for bad in ("0", "-1", "7", "nan", "x"):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                tv.parser().parse_args(["volume", "up", "--step-db", bad])

    def test_status_is_read_only(self):
        fake = world("ARD")
        code, out, _ = run(["status"], fake)
        self.assertEqual(code, 0)
        self.assertIn("ARD Live: muted=false db=-10.0", out)
        self.assertEqual(fake.calls, [])

    def test_failure_does_not_leak_the_message(self):
        def boom():
            raise RuntimeError("secret-token-123")

        out, err = io.StringIO(), io.StringIO()
        code = tv.run(tv.parser().parse_args(["mute"]), client_factory=boom, out=out, err=err)
        self.assertEqual(code, tv.EXIT_ERROR)
        self.assertNotIn("secret-token-123", err.getvalue() + out.getvalue())

    def test_unverified_mute_is_an_error(self):
        fake = world("ARD")
        fake.set_input_mute = lambda name, muted: fake.calls.append(("mute", name, muted))
        code, _, err = run(["mute"], fake)
        self.assertEqual(code, tv.EXIT_ERROR)
        self.assertIn("did not report muted", err)


if __name__ == "__main__":
    unittest.main()
