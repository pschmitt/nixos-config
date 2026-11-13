"""Offline regression tests; all console URLs and VNC traffic are synthetic."""

import asyncio
import importlib.util
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from websockets.asyncio.server import serve

SPEC = importlib.util.spec_from_file_location(
    "console_tui", Path(__file__).with_name("tui.py")
)
tui = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tui)


class UrlTests(unittest.TestCase):
    def test_encoded_path(self):
        target, origin = tui.websocket_target(
            "https://console.example/vnc.html?path=%2Fwebsockify%3Ftoken%3Dfixture"
        )
        self.assertEqual(target, "wss://console.example/websockify?token=fixture")
        self.assertEqual(origin, "https://console.example")

    def test_nova_token(self):
        target, _ = tui.websocket_target(
            "https://console.example/vnc_auto.html?token=fixture"
        )
        self.assertEqual(target, "wss://console.example/websockify?token=fixture")

    def test_plain_http(self):
        target, origin = tui.websocket_target(
            "http://127.0.0.1:8000/vnc.html?path=websockify"
        )
        self.assertEqual(target, "ws://127.0.0.1:8000/websockify")
        self.assertEqual(origin, "http://127.0.0.1:8000")

    def test_websocket_url(self):
        url = "wss://console.example/websockify?token=fixture"
        self.assertEqual(tui.websocket_target(url), (url, "https://console.example"))

    def test_reject_invalid_or_cross_origin(self):
        for url in (
            "not-a-url",
            "https://console.example/vnc.html",
            "https://user:password@console.example/?token=fixture",
            "https://console.example/?path=//other.example/websockify",
            "https://console.example/?path=ws://console.example/websockify",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                tui.websocket_target(url)

    def test_viewer_flags(self):
        for viewer, endpoint in (
            ("desktui", "127.0.0.1::43210"),
            ("farsee", "127.0.0.1:43210"),
        ):
            command = tui.viewer_command(viewer, 43210, True)
            self.assertIn(endpoint, command)
            self.assertIn("--view-only", command)
            self.assertNotIn("--view-only", tui.viewer_command(viewer, 43210, False))
            self.assertTrue("--no-clipboard" in command or "--clipboard" in command)

    def test_no_chrome_hides_desktui_status(self):
        self.assertNotIn("--no-status", tui.viewer_command("desktui", 1, False))
        self.assertIn("--no-status", tui.viewer_command("desktui", 1, False, False))
        self.assertNotIn("--no-status", tui.viewer_command("farsee", 1, False, False))

    def test_desktui_skips_probe_only_inside_tmux(self):
        with patch.dict(os.environ, {"TMUX": "/tmp/tmux-1/default,1,0"}):
            self.assertIn("--force", tui.viewer_command("desktui", 1, False))
            self.assertNotIn("--force", tui.viewer_command("farsee", 1, False))
        with patch.dict(os.environ, {}, clear=True):
            self.assertNotIn("--force", tui.viewer_command("desktui", 1, False))


class BridgeTests(unittest.IsolatedAsyncioTestCase):
    async def run_bridge(self, handler, script):
        original_command = tui.viewer_command

        def fake_viewer(viewer, port, view_only, chrome=True):
            original_command(viewer, port, view_only, chrome)
            return [sys.executable, "-I", "-c", script, str(port)]

        async with serve(handler, "127.0.0.1", 0, subprotocols=["binary"]) as server:
            port = server.sockets[0].getsockname()[1]
            with (
                patch.object(tui, "viewer_command", fake_viewer),
                patch.object(
                    tui,
                    "open",
                    lambda *args, **kwargs: open(os.devnull, "rb"),
                    create=True,
                ),
            ):
                return await asyncio.wait_for(
                    tui.run_viewer(
                        f"ws://127.0.0.1:{port}/websockify",
                        "http://127.0.0.1",
                        "desktui",
                        True,
                    ),
                    5,
                )

    async def test_bidirectional_relay_and_exit(self):
        received = []

        async def websocket(ws):
            received.append(await ws.recv())
            await ws.send(b"RFB fixture reply")
            await ws.wait_closed()

        script = (
            "import socket, sys; "
            "s=socket.create_connection(('127.0.0.1', int(sys.argv[1]))); "
            "s.sendall(b'RFB fixture request'); "
            "assert s.recv(100) == b'RFB fixture reply'; s.close()"
        )
        self.assertEqual(await self.run_bridge(websocket, script), 0)
        self.assertEqual(received, [b"RFB fixture request"])

    async def test_nonbinary_failure_stops_viewer(self):
        async def websocket(ws):
            await ws.send("not binary")
            await ws.wait_closed()

        script = (
            "import socket, sys, time; "
            "s=socket.create_connection(('127.0.0.1', int(sys.argv[1]))); "
            "time.sleep(30)"
        )
        self.assertEqual(await self.run_bridge(websocket, script), 1)

    async def test_viewer_exit_without_connection(self):
        async def websocket(ws):
            await ws.wait_closed()

        self.assertEqual(await self.run_bridge(websocket, "import sys; sys.exit(7)"), 7)


@unittest.skipUnless(
    os.environ.get("OPENSTACK_CONSOLE_WRAPPER"), "zsh wrapper not supplied"
)
class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.wrapper = Path(os.environ["OPENSTACK_CONSOLE_WRAPPER"])

    def invoke(self, args, prefix=""):
        return subprocess.run(
            [
                "zsh",
                "-f",
                "-c",
                prefix
                + '\nwrapper=$1; shift; function console_run { source "$wrapper"; }; console_run "$@"',
                "test",
                str(self.wrapper),
                *args,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_help(self):
        result = self.invoke(["--help"])
        self.assertEqual(result.returncode, 0)
        self.assertIn("--viewer", result.stdout)

    def test_missing_server(self):
        self.assertEqual(self.invoke(["--tui"]).returncode, 2)

    def test_bad_viewer(self):
        self.assertEqual(self.invoke(["--viewer", "missing", "fixture"]).returncode, 2)

    def test_browser_delegation(self):
        result = self.invoke(
            ["--os-cloud", "fixture-cloud", "fixture-server"],
            "function openstack::console-open { printf '%s\\n' \"$@\"; }",
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.splitlines(), ["--project", "fixture-cloud", "fixture-server"]
        )


@unittest.skipUnless(
    os.environ.get("OPENSTACK_CONSOLE_WRAPPER"), "zsh wrapper not supplied"
)
class EndToEndTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self, viewer="desktui", provider_fails=False, automatic=False):
        received = []

        async def websocket(ws):
            received.append(await ws.recv())
            await ws.send(b"fixture reply")
            await ws.wait_closed()

        with tempfile.TemporaryDirectory(prefix="console-wrapper-test-") as directory:
            root = Path(directory)
            for name, body in {
                "console-tui": (
                    "import os, sys\n"
                    f"os.execv(sys.executable, [sys.executable, '-I', {str(Path(__file__).with_name('tui.py'))!r}, *sys.argv[1:]])\n"
                ),
                viewer: (
                    "import os, socket, sys\n"
                    "from pathlib import Path\n"
                    "assert sys.stdin.isatty()\n"
                    "Path(os.environ['FIXTURE_ARGS']).write_text('\\n'.join(sys.argv))\n"
                    "endpoint = next(arg for arg in sys.argv if arg.startswith('127.0.0.1:'))\n"
                    "port = int(endpoint.rsplit(':', 1)[1])\n"
                    "with socket.create_connection(('127.0.0.1', port)) as s:\n"
                    "    s.sendall(b'fixture request')\n"
                    "    assert s.recv(100) == b'fixture reply'\n"
                ),
            }.items():
                executable = root / name
                executable.write_text(f"#!{sys.executable}\n" + body)
                executable.chmod(0o700)
            async with serve(
                websocket, "127.0.0.1", 0, subprotocols=["binary"]
            ) as server:
                port = server.sockets[0].getsockname()[1]
                environment = os.environ.copy()
                environment.update(
                    PATH=str(root) + os.pathsep + environment["PATH"],
                    FIXTURE_URL=f"ws://127.0.0.1:{port}/websockify?token=fixture-private-value",
                    FIXTURE_ARGS=str(root / "arguments"),
                    OPENSTACK_BIN="fixture_openstack",
                )
                for variable in ("TMUX", "OPENSTACK_CONSOLE_VIEWER"):
                    environment.pop(variable, None)
                wrapper = Path(os.environ["OPENSTACK_CONSOLE_WRAPPER"])
                provider = (
                    "function fixture_openstack { print -ru2 -- $FIXTURE_URL; return 1; }"
                    if provider_fails
                    else "function fixture_openstack { print -r -- $FIXTURE_URL; }"
                )
                script = (
                    provider
                    + '\nwrapper=$1; shift; function console_run { source "$wrapper"; }; '
                    + 'console_run "$@"'
                )
                master, slave = pty.openpty()

                # The bridge opens /dev/tty, so the child needs its own controlling tty.
                def controlling_tty():
                    import fcntl
                    import termios

                    os.setsid()
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)

                process = await asyncio.create_subprocess_exec(
                    "zsh",
                    "-f",
                    "-c",
                    script,
                    "fixture",
                    str(wrapper),
                    *(["--tui"] if automatic else ["--viewer", viewer]),
                    "--view-only",
                    "fixture-server",
                    env=environment,
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    preexec_fn=controlling_tty,
                )
                os.close(slave)
                try:
                    result = await asyncio.wait_for(process.wait(), 10)
                    output = bytearray()
                    while True:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError:
                            break
                        if not chunk:
                            break
                        output.extend(chunk)
                finally:
                    if process.returncode is None:
                        process.kill()
                        await process.wait()
                    os.close(master)
                self.assertNotIn(b"fixture-private-value", output)
                self.assertEqual(result, 1 if provider_fails else 0, output.decode())
                if not provider_fails:
                    args = (root / "arguments").read_text().splitlines()
                    self.assertIn("--view-only", args)
                    self.assertEqual(received, [b"fixture request"])
                    self.assertTrue("--no-clipboard" in args or "--clipboard" in args)
                return result

    async def test_desktui_wrapper(self):
        await self.exercise()

    async def test_farsee_wrapper(self):
        await self.exercise(viewer="farsee")

    async def test_automatic_viewer(self):
        await self.exercise(automatic=True)

    async def test_provider_error_is_redacted(self):
        await self.exercise(provider_fails=True)


if __name__ == "__main__":
    unittest.main()
