import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "bridge", Path(__file__).with_name("obs-broadcast-audio.py")
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class AudioBridgeTests(unittest.TestCase):
    def test_status_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            for data in (None, "", "bad\nenabled\nrouting\n\n", "100\nenabled\nrouting\n\n"):
                if data is not None:
                    (directory / "status").write_text(data)
                status = bridge.read_status(directory, now=103)
                self.assertFalse(status["fresh"])

    def test_status_heartbeat(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "status").write_text("100\nenabled\nrouting\n\n")
            status = bridge.read_status(directory, now=101)
            self.assertTrue(status["fresh"])
            self.assertTrue(status["enabled"])
            self.assertTrue(status["routing"])
            self.assertFalse(bridge.read_status(directory, now=99)["fresh"])

    def test_loopback_is_isolated(self):
        command = bridge.bridge_command()
        self.assertEqual(command[command.index("--capture") + 1], "obs_broadcast")
        capture = json.loads(command[command.index("--capture-props") + 1])
        playback = json.loads(command[command.index("--playback-props") + 1])
        self.assertTrue(capture["stream.capture.sink"])
        self.assertTrue(capture["node.dont-fallback"])
        self.assertFalse(playback["node.autoconnect"])
        self.assertTrue(playback["meeting-mic.feed"])

    def test_cleanup_only_unloads_the_owned_module(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            for owner, expected in ((42, 2), (99, 1)):
                (directory / "module").write_text("42")
                with patch.object(bridge, "run", side_effect=[json.dumps([
                    {"name": "obs_broadcast", "owner_module": owner}
                ]), ""]) as run:
                    bridge.cleanup(directory)
                    self.assertEqual(run.call_count, expected)
                    if owner == 42:
                        run.assert_called_with("pactl", "unload-module", "42")

    def test_missing_meeting_microphone_creates_nothing(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(bridge, "run", return_value="[]") as run:
            with self.assertRaisesRegex(RuntimeError, "unavailable"):
                bridge.serve(Path(directory))
            self.assertEqual(run.call_count, 1)
            self.assertFalse((Path(directory) / "requested").exists())

    def test_existing_sink_is_not_taken_over(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(bridge, "run", side_effect=[
            '[{"name":"meeting_source"}]', '[{"name":"obs_broadcast"}]'
        ]) as run:
            with self.assertRaisesRegex(RuntimeError, "ownership"):
                bridge.serve(Path(directory))
            self.assertEqual(run.call_count, 2)

    def test_stale_heartbeat_closes_bridge_and_unloads_owned_sink(self):
        states = [
            {"fresh": True, "enabled": True, "routing": True, "error": ""},
            {"fresh": False, "enabled": True, "routing": True, "error": ""},
        ]
        with tempfile.TemporaryDirectory() as directory, patch.object(bridge, "run", side_effect=[
            '[{"name":"meeting_source"}]', '[]', '42', ''
        ]) as run, patch.object(bridge, "read_status", side_effect=states + [
            {"fresh": True, "enabled": False, "routing": False, "error": ""}
        ]), patch.object(
            bridge.subprocess, "Popen"
        ) as popen, patch.object(bridge.time, "sleep"):
            popen.return_value.poll.return_value = None
            with self.assertRaisesRegex(RuntimeError, "route closed"):
                bridge.serve(Path(directory))
            popen.return_value.terminate.assert_called_once()
            run.assert_called_with("pactl", "unload-module", "42")
            self.assertFalse((Path(directory) / "requested").exists())

    def test_switch_away_stops_loopback(self):
        states = [
            {"fresh": True, "enabled": True, "routing": True, "error": ""},
            {"fresh": True, "enabled": True, "routing": False, "error": ""},
            {"fresh": False, "enabled": False, "routing": False, "error": ""},
        ]
        with tempfile.TemporaryDirectory() as directory, patch.object(bridge, "run", side_effect=[
            '[{"name":"meeting_source"}]', '[]', '42', ''
        ]), patch.object(bridge, "read_status", side_effect=states + [
            {"fresh": True, "enabled": False, "routing": False, "error": ""}
        ]), patch.object(
            bridge.subprocess, "Popen"
        ) as popen, patch.object(bridge.time, "sleep"):
            popen.return_value.poll.return_value = None
            with self.assertRaisesRegex(RuntimeError, "route closed"):
                bridge.serve(Path(directory))
            popen.assert_called_once()
            popen.return_value.terminate.assert_called_once()


if __name__ == "__main__":
    unittest.main()
