import io
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import termuxpp_adb_devices as devices  # noqa: E402


spec = importlib.util.spec_from_file_location("termuxpp_adb_ssh_proxy", Path(__file__).with_name("termuxpp-adb-ssh-proxy.py"))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

ALIAS = devices.Alias("one", ("USB1",), ssh_port=2200, ssh_start_argv=("sh", "-c", "start"))


def args(**override):
    values = dict(no_start=False, probe_timeout=3, start_timeout=5, ready_timeout=10, credential_dir=None)
    values.update(override)
    return mock.Mock(**values)


class ProbeTests(unittest.TestCase):
    @mock.patch.object(proxy.subprocess, "run")
    def test_probe_uses_detached_stdin_and_bounded_nc(self, run):
        run.return_value = mock.Mock(returncode=0, stdout=b"SSH-2.0-test\r\n", stderr=b"")
        self.assertTrue(proxy.probe_listener("S", 2222, 3))
        self.assertEqual(run.call_args.args[0], ["adb", "-s", "S", "shell", "-T", "toybox", "nc", "-w", "2",
                                                 "127.0.0.1", "2222"])
        self.assertIs(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["timeout"], 3)

    @mock.patch.object(proxy.subprocess, "run")
    def test_only_connection_refused_is_down(self, run):
        run.return_value = mock.Mock(returncode=1, stdout=b"", stderr=b"nc: connect: Connection refused\n")
        self.assertFalse(proxy.probe_listener("S", 2222, 3))
        for stderr in (b"error: device offline", b"adb: no devices/emulators found", b"toybox: nc: Unknown option 'w'",
                       b"/system/bin/sh: toybox: inaccessible or not found", b"nc: connect: Permission denied", b""):
            run.return_value = mock.Mock(returncode=1, stdout=b"", stderr=stderr)
            with self.assertRaises(proxy.ProbeError):
                proxy.probe_listener("S", 2222, 3)
        run.return_value = mock.Mock(returncode=127, stdout=b"", stderr=b"")
        with self.assertRaises(proxy.ProbeError):
            proxy.probe_listener("S", 2222, 3)
        run.side_effect = subprocess.TimeoutExpired("adb", 3)
        with self.assertRaises(proxy.ProbeError):
            proxy.probe_listener("S", 2222, 3)


class ArgsTests(unittest.TestCase):
    def test_timeouts_must_be_finite_and_positive(self):
        for option in ("--probe-timeout", "--start-timeout", "--ready-timeout"):
            for value in ("nan", "inf", "-inf", "0", "-1", "x"):
                with self.subTest(option=option, value=value), mock.patch.object(proxy.sys, "stderr", io.StringIO()):
                    with self.assertRaises(SystemExit):
                        proxy.parse_args(["--serial", "S", option, value])
        self.assertEqual(proxy.parse_args(["--serial", "S", "--start-timeout", "2.5"]).start_timeout, 2.5)


class EnsureListenerTests(unittest.TestCase):
    device = devices.Device("USB1", Path("/credentials"), ALIAS)

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", return_value=True)
    def test_running_listener_is_never_started(self, probe, start):
        proxy.ensure_listener(self.device, 2200, args())
        start.assert_not_called()

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", return_value=False)
    def test_down_without_start_config_or_with_no_start_fails(self, probe, start):
        for device, options in ((devices.Device("S", Path("/c"), None), {}), (self.device, {"no_start": True})):
            with self.assertRaisesRegex(RuntimeError, "no start command"):
                proxy.ensure_listener(device, 2200, args(**options))
        start.assert_not_called()

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", side_effect=proxy.ProbeError("x"))
    def test_inconclusive_probe_does_not_start(self, probe, start):
        with self.assertRaises(proxy.ProbeError):
            proxy.ensure_listener(self.device, 2200, args())
        start.assert_not_called()

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", side_effect=[False, proxy.ProbeError("x"), False, True])
    def test_down_starts_with_alias_command_then_retries(self, probe, start):
        sleeps = []
        proxy.ensure_listener(self.device, 2200, args(), sleep=sleeps.append)
        start.assert_called_once_with("USB1", Path("/credentials"), ("sh", "-c", "start"), 5)
        self.assertEqual(sleeps, [1, 1])

    @mock.patch.object(proxy.sys, "stderr", new_callable=io.StringIO)
    @mock.patch.object(proxy, "start_daemon", side_effect=RuntimeError("SSH start command exited with status 3."))
    @mock.patch.object(proxy, "probe_listener", side_effect=[False, True])
    def test_nonzero_start_still_succeeds_when_listener_comes_up(self, probe, start, stderr):
        proxy.ensure_listener(self.device, 2200, args(), sleep=lambda s: None)
        start.assert_called_once()
        self.assertIn("status 3", stderr.getvalue())

    @mock.patch.object(proxy.sys, "stderr", new_callable=io.StringIO)
    @mock.patch.object(proxy, "start_daemon", side_effect=[TimeoutError("timed out"), OSError("boom")])
    @mock.patch.object(proxy, "probe_listener", side_effect=[False, True])
    def test_start_timeout_or_oserror_rechecks_listener(self, probe, start, stderr):
        proxy.ensure_listener(self.device, 2200, args(), sleep=lambda s: None)
        self.assertEqual(probe.call_count, 2)

    @mock.patch.object(proxy.sys, "stderr", new_callable=io.StringIO)
    @mock.patch.object(proxy, "start_daemon", side_effect=RuntimeError("SSH start command exited with status 3."))
    @mock.patch.object(proxy, "probe_listener", return_value=False)
    def test_failure_reports_start_error_only_after_wait(self, probe, start, stderr):
        clock = iter(range(0, 100, 4))
        with self.assertRaisesRegex(RuntimeError, "did not come up in time.*status 3"):
            proxy.ensure_listener(self.device, 2200, args(), sleep=lambda s: None,
                                  monotonic=lambda: next(clock))
        self.assertGreater(probe.call_count, 1)

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", return_value=False)
    def test_ambiguous_credentials_block_start_only(self, probe, start):
        device = devices.Device("USB1", Path("/c"), ALIAS, "several of its serials")
        with self.assertRaisesRegex(RuntimeError, "several of its serials"):
            proxy.ensure_listener(device, 2200, args())
        start.assert_not_called()

    @mock.patch.object(proxy, "start_daemon")
    @mock.patch.object(proxy, "probe_listener", return_value=False)
    def test_wait_is_bounded(self, probe, start):
        clock = iter(range(0, 100, 4))
        with self.assertRaisesRegex(RuntimeError, "did not come up"):
            proxy.ensure_listener(self.device, 2200, args(), sleep=lambda s: None,
                                  monotonic=lambda: next(clock))
        self.assertLess(probe.call_count, 6)


class StartDaemonTests(unittest.TestCase):
    @mock.patch.object(proxy.subprocess, "Popen")
    def test_runs_cli_mtls_with_detached_stdin_and_stderr_output(self, popen):
        popen.return_value.wait.return_value = 0
        proxy.start_daemon("S", Path("/c"), ("sh", "-c", "x"), 5)
        command = popen.call_args.args[0]
        self.assertEqual(command[:2], [proxy.sys.executable, "-I"])
        self.assertEqual(command[3:], ["--serial", "S", "--mode", "mtls", "--credential-dir", "/c", "--outer", "--",
                                       "sh", "-c", "x"])
        self.assertIs(popen.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertIs(popen.call_args.kwargs["stdout"], proxy.sys.stderr)
        self.assertIs(popen.call_args.kwargs["stderr"], proxy.sys.stderr)
        popen.return_value.wait.assert_called_once_with(timeout=5)

    @mock.patch.object(proxy.subprocess, "Popen")
    def test_nonzero_status_raises(self, popen):
        popen.return_value.wait.return_value = 3
        with self.assertRaisesRegex(RuntimeError, "status 3"):
            proxy.start_daemon("S", Path("/c"), ("x",), 5)

    @mock.patch.object(proxy.subprocess, "Popen")
    def test_wall_clock_timeout_interrupts_then_kills(self, popen):
        child = popen.return_value
        child.wait.side_effect = [subprocess.TimeoutExpired("c", 5), subprocess.TimeoutExpired("c", 5), 0]
        with self.assertRaisesRegex(RuntimeError, "did not finish within 5s"):
            proxy.start_daemon("S", Path("/c"), ("x",), 5)
        child.send_signal.assert_called_once_with(proxy.signal.SIGINT)
        child.kill.assert_called_once_with()


class MainTests(unittest.TestCase):
    @mock.patch.object(proxy.os, "execvp")
    @mock.patch.object(proxy, "ensure_listener")
    @mock.patch.object(proxy.devices, "resolve_device")
    def test_resolves_once_and_execs_nc_for_same_serial(self, resolve, ensure, execvp):
        resolve.return_value = devices.Device("USB1", Path("/c"), ALIAS)
        proxy.main(["--serial", "one"])
        resolve.assert_called_once()
        self.assertEqual(ensure.call_args.args[0:2], (resolve.return_value, 2200))
        execvp.assert_called_once_with("adb", ["adb", "-s", "USB1", "shell", "-T", "toybox", "nc", "127.0.0.1", "2200"])

    @mock.patch.object(proxy.os, "execvp")
    @mock.patch.object(proxy, "ensure_listener")
    @mock.patch.object(proxy.devices, "resolve_device")
    def test_raw_serial_uses_default_port_and_port_option_wins(self, resolve, ensure, execvp):
        resolve.return_value = devices.Device("RAW", Path("/c"), None)
        proxy.main(["--serial", "RAW"])
        self.assertEqual(execvp.call_args.args[1][-1], "2222")
        proxy.main(["--serial", "RAW", "--port", "2300"])
        self.assertEqual(execvp.call_args.args[1][-1], "2300")

    @mock.patch.object(proxy.os, "execvp")
    @mock.patch.object(proxy.devices, "resolve_device", side_effect=RuntimeError("ambiguous"))
    def test_failure_never_execs(self, resolve, execvp):
        self.assertEqual(proxy.main(["--serial", "one"]), 1)
        execvp.assert_not_called()


if __name__ == "__main__":
    unittest.main()
