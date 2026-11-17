import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
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

    def test_local_branch_is_monitor_only_and_follows_the_default_output(self):
        command = bridge.local_command()
        self.assertEqual(command[command.index("--capture") + 1], "obs_broadcast")
        capture = json.loads(command[command.index("--capture-props") + 1])
        playback = json.loads(command[command.index("--playback-props") + 1])
        self.assertTrue(capture["stream.capture.sink"])
        self.assertTrue(capture["node.dont-fallback"])
        self.assertTrue(capture["node.dont-reconnect"])
        # No explicit target and no pinning: the session manager follows the
        # default output (speakers, headphones, Bluetooth) and its changes.
        self.assertNotIn("--playback", command)
        self.assertNotIn("target.object", playback)
        self.assertNotIn("node.dont-fallback", playback)
        self.assertNotIn("node.dont-reconnect", playback)
        self.assertNotIn("node.autoconnect", playback)
        self.assertNotIn("meeting-mic.feed", playback)
        self.assertNotEqual(playback["node.name"], "obs_broadcast_feed")
        self.assertNotIn("meeting_source", " ".join(command))

    def test_output_loop_detection(self):
        sinks = json.dumps([{"index": 7, "name": "obs_broadcast"}, {"index": 9, "name": "speakers"}])

        def streams(sink):
            return json.dumps([
                {"sink": 7, "properties": {"node.name": "other"}},
                {"sink": sink, "properties": {"node.name": "obs_broadcast_local"}},
            ])

        cases = (
            ("speakers", streams(9), False),
            ("bt_headset", streams(9), False),
            ("obs_broadcast", streams(9), True),
            ("speakers", streams(7), True),
        )
        for default, inputs, expected in cases:
            with patch.object(bridge, "run", side_effect=[default, sinks, inputs]):
                self.assertEqual(bridge.local_output_loops(), expected, (default, inputs))
        with patch.object(bridge, "run", side_effect=["obs_broadcast"]) as run:
            self.assertTrue(bridge.local_output_loops())
            self.assertEqual(run.call_count, 1)

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
        ) as popen, patch.object(bridge.time, "sleep"), \
             patch.object(bridge, "local_output_loops", return_value=False):
            popen.return_value.poll.return_value = None
            with self.assertRaisesRegex(RuntimeError, "route closed"):
                bridge.serve(Path(directory))
            self.assertEqual(popen.call_count, 2)
            self.assertEqual(popen.return_value.terminate.call_count, 2)
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
        ) as popen, patch.object(bridge.time, "sleep"), \
             patch.object(bridge, "local_output_loops", return_value=False):
            popen.return_value.poll.return_value = None
            with self.assertRaisesRegex(RuntimeError, "route closed"):
                bridge.serve(Path(directory))
            commands = [call.args[0] for call in popen.call_args_list]
            self.assertEqual(commands, [bridge.bridge_command(), bridge.local_command()])
            self.assertEqual(popen.return_value.terminate.call_count, 2)

    def serve_running(self, processes, loops, extra_states=()):
        ready = {"fresh": True, "enabled": True, "routing": True, "error": ""}
        off = dict(ready, enabled=False, routing=False)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        with patch.object(bridge, "run", side_effect=[
            '[{"name":"meeting_source"}]', '[]', '42', ''
        ]) as run, patch.object(bridge, "read_status", side_effect=[ready] * 6 + [off]), \
             patch.object(bridge.subprocess, "Popen", side_effect=processes) as popen, \
             patch.object(bridge.time, "sleep"), \
             patch.object(bridge, "GUARD_INTERVAL", 0), \
             patch.object(bridge, "local_output_loops", side_effect=loops) as guard:
            with self.assertRaisesRegex(RuntimeError, "route closed"):
                bridge.serve(Path(directory.name))
        return run, popen, guard

    def test_default_output_becoming_the_obs_sink_closes_both_branches(self):
        processes = [unittest.mock.Mock(), unittest.mock.Mock()]
        for process in processes:
            process.poll.return_value = None
        run, _, guard = self.serve_running(processes, [False, False, True])
        self.assertEqual(guard.call_count, 3)
        for process in processes:
            process.terminate.assert_called_once()
        run.assert_called_with("pactl", "unload-module", "42")

    def test_loop_at_start_launches_nothing(self):
        run, popen, _ = self.serve_running([], [True])
        popen.assert_not_called()
        run.assert_called_with("pactl", "unload-module", "42")

    def test_either_branch_exiting_closes_both(self):
        for dead in (0, 1):
            processes = [unittest.mock.Mock(), unittest.mock.Mock()]
            for process in processes:
                process.poll.return_value = None
            processes[dead].poll.side_effect = [None, 1]
            self.serve_running(processes, [False] * 5)
            for process in processes:
                process.terminate.assert_called_once()

    def test_stop_signals_the_local_branch_first(self):
        events = []
        processes = []
        for name in ("meeting", "local"):
            process = unittest.mock.Mock()
            process.terminate.side_effect = lambda name=name: events.append(("terminate", name))
            process.wait.side_effect = lambda timeout, name=name: events.append(("wait", name))
            processes.append(process)
        bridge.stop_processes(processes)
        self.assertEqual(events, [
            ("terminate", "local"), ("terminate", "meeting"),
            ("wait", "local"), ("wait", "meeting"),
        ])

    def test_a_stuck_branch_is_killed_without_delaying_the_other_signal(self):
        local, meeting = unittest.mock.Mock(), unittest.mock.Mock()
        local.wait.side_effect = [subprocess.TimeoutExpired("pw-loopback", 2), None]
        bridge.stop_processes([meeting, local])
        local.terminate.assert_called_once()
        meeting.terminate.assert_called_once()
        local.kill.assert_called_once()
        meeting.kill.assert_not_called()

    def test_failed_local_start_stops_the_meeting_branch(self):
        meeting = unittest.mock.Mock()
        with patch.object(bridge, "local_output_loops", return_value=False), \
             patch.object(bridge.subprocess, "Popen", side_effect=[meeting, OSError("boom")]):
            with self.assertRaises(OSError):
                bridge.start_bridges()
        meeting.terminate.assert_called_once()


    def run_on(self, directory, start_returncode):
        calls = []

        def fake_run(args, check=False, **kwargs):
            args = list(args)
            calls.append(args)
            returncode = {"is-active": 3, "reset-failed": 1, "start": start_returncode}[args[2]]
            if check and returncode:
                raise subprocess.CalledProcessError(returncode, args)
            return subprocess.CompletedProcess(args, returncode, stdout="", stderr="")

        status = {"fresh": True, "enabled": True, "routing": False, "error": ""}
        (directory / "requested").write_text("")
        with patch.object(bridge.subprocess, "run", side_effect=fake_run), \
             patch.object(bridge, "read_status", return_value=status), \
             patch.object(sys, "argv", ["obs-broadcast-audio", "on"]), \
             patch.dict(bridge.os.environ, {"XDG_RUNTIME_DIR": str(directory.parent)}):
            bridge.main()
        return calls

    def test_on_ignores_reset_failed_for_never_started_unit(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "obs-broadcast-audio"
            directory.mkdir()
            calls = self.run_on(directory, start_returncode=0)
        self.assertEqual(
            [call[2] for call in calls], ["is-active", "reset-failed", "start"]
        )

    def test_on_still_fails_when_start_fails(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / "obs-broadcast-audio"
            directory.mkdir()
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_on(directory, start_returncode=1)


if __name__ == "__main__":
    unittest.main()
