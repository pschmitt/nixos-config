import base64
import hashlib
import hmac
import importlib.util
import os
from pathlib import Path
import socket
import shutil
import subprocess
import threading
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location("termuxpp_adb_shell", Path(__file__).with_name("termuxpp-adb-shell.py"))
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


def setUpModule():
    # Keep the suite independent of any real device alias configuration.
    isolated = mock.patch.object(cli.devices, "DEFAULT_CONFIG", Path("/nonexistent/termuxpp-adb-devices.json"))
    environment = mock.patch.dict(os.environ)
    isolated.start()
    environment.start()
    os.environ.pop(cli.devices.CONFIG_ENV, None)
    unittest.addModuleCleanup(isolated.stop)
    unittest.addModuleCleanup(environment.stop)


class BootstrapTests(unittest.TestCase):
    def exchange(self, fake_server=False):
        client, server = socket.socketpair()
        token = b"test-token-not-a-credential"
        received = []
        errors = []

        def serve():
            try:
                request = b""
                while not request.endswith(b"\n"):
                    request += server.recv(1)
                version, operation, encoded_nonce = request.strip().split(b" ")
                received.append(request)
                nonce = base64.b64decode(encoded_nonce)
                server_nonce = os.urandom(32)
                public_key = b"public-key-fixture"
                self.assertEqual(version, b"TERMUXPP/BOOT/3")
                existing_certificate = b"existing-server-cert"
                transcript = (version + b"\0" + operation + b"\0" + nonce + server_nonce
                              + hashlib.sha256(public_key).digest() + hashlib.sha256(existing_certificate).digest())
                def mac(role, data):
                    return hmac.digest(token, role + b"\0" + data, "sha256")
                cli.send_frame(server, public_key)
                cli.send_frame(server, server_nonce)
                cli.send_frame(server, existing_certificate)
                cli.send_frame(server, bytes(32) if fake_server else mac(b"server", transcript))
                if fake_server:
                    received.append(server.recv(1024))
                    return
                self.assertEqual(cli.receive_frame(server), mac(b"client", transcript))
                materials = [cli.receive_frame(server) for _ in range(5)]
                proof = cli.receive_frame(server)
                digest = hashlib.sha256()
                for data in materials:
                    digest.update(len(data).to_bytes(4, "big"))
                    digest.update(data)
                expected = mac(b"material", transcript + digest.digest())
                self.assertEqual(proof, expected)
                server.sendall(b"OK\n")
            except Exception as error:
                errors.append(error)
            finally:
                server.close()

        thread = threading.Thread(target=serve)
        thread.start()
        with mock.patch.object(cli.socket, "create_connection", return_value=client):
            if fake_server:
                with self.assertRaisesRegex(RuntimeError, "server authentication"):
                    cli.bootstrap(token, "PROVISION", lambda key, existing: (b"key", b"cert", b"ca", b"client-cert", b"client-name"))
            else:
                cli.bootstrap(token, "PROVISION", lambda key, existing: (b"key", b"cert", b"ca", b"client-cert", b"client-name"))
        thread.join(5)
        self.assertFalse(thread.is_alive())
        if errors:
            raise errors[0]
        self.assertNotIn(token, received[0])
        if fake_server:
            self.assertEqual(received[1], b"")

    def test_provision_authenticates_exchange(self):
        self.exchange()

    def test_fake_listener_receives_no_token_or_provisioning_material(self):
        self.exchange(fake_server=True)


class CredentialTests(unittest.TestCase):
    @mock.patch("builtins.print")
    @mock.patch.object(cli.ssl, "PEM_cert_to_DER_cert", return_value=b"certificate-fixture")
    @mock.patch.object(cli, "request_token", return_value=b"test-token-not-a-credential")
    def test_provision_preserves_requested_client_name(self, token, certificate, output):
        def openssl(*args, **kwargs):
            for option in ("-out", "-keyout"):
                if option in args:
                    Path(args[args.index(option) + 1]).write_bytes(b"fixture")

        def provision(access_token, operation, material_factory):
            self.assertEqual(operation, "PROVISION")
            materials = material_factory(b"public-key-fixture", b"\0")
            self.assertEqual(materials[-1], b"Test workstation")

        with cli.tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(cli, "run_openssl", side_effect=openssl):
                with mock.patch.object(cli, "bootstrap", side_effect=provision):
                    cli.create_credentials(Path(directory) / "credentials", "Test workstation")


class ConnectionTests(unittest.TestCase):
    @mock.patch.object(cli.time, "sleep")
    @mock.patch.object(cli.socket, "create_connection")
    def test_retries_transient_handshake_eof(self, create_connection, sleep):
        raw = mock.Mock()
        create_connection.return_value = raw
        context = mock.Mock()
        connected = mock.Mock()
        context.wrap_socket.side_effect = [cli.ssl.SSLEOFError(), connected]
        self.assertIs(cli.connect_tls(context), connected)
        self.assertEqual(create_connection.call_count, 2)
        raw.close.assert_called_once()
        sleep.assert_called_once_with(1)

    @mock.patch.object(cli.time, "sleep")
    @mock.patch.object(cli.socket, "create_connection")
    def test_does_not_retry_certificate_failure(self, create_connection, sleep):
        raw = mock.Mock()
        create_connection.return_value = raw
        context = mock.Mock()
        context.wrap_socket.side_effect = cli.ssl.SSLCertVerificationError()
        with self.assertRaises(cli.ssl.SSLCertVerificationError):
            cli.connect_tls(context)
        raw.close.assert_called_once()
        sleep.assert_not_called()


class AuthorizationTests(unittest.TestCase):
    @mock.patch.object(cli, "authenticated_connection")
    def test_revoke_validates_full_fingerprint_before_connecting(self, connect):
        for fingerprint in ("", "bad", "A" * 64, "a" * 63, "a" * 64 + "\n"):
            with self.subTest(fingerprint=fingerprint), self.assertRaises(RuntimeError):
                cli.manage_authorizations(Path("unused"), fingerprint)
        connect.assert_not_called()

    @mock.patch.object(cli, "authenticated_connection")
    def test_revoke_is_an_authenticated_tls_operation(self, connect):
        connection = connect.return_value.__enter__.return_value
        connection.recv.side_effect = [b"O", b"K", b"\n"]
        cli.manage_authorizations(Path("unused"), "a" * 64)
        connection.sendall.assert_called_once_with(b"REVOKE " + b"a" * 64 + b"\n")

    @mock.patch.object(cli, "authenticated_connection")
    @mock.patch.object(cli, "receive_frame", return_value=b'[{"name":"client","fingerprint":"abc"}]')
    @mock.patch("builtins.print")
    def test_list_is_an_authenticated_tls_operation(self, output, receive, connect):
        cli.manage_authorizations(Path("unused"))
        connection = connect.return_value.__enter__.return_value
        connection.sendall.assert_called_once_with(b"LIST\n")
        self.assertIn('"name": "client"', output.call_args.args[0])


class ForwardingTests(unittest.TestCase):
    @mock.patch.object(cli.subprocess, "run")
    def test_forwards_are_dynamic_and_cleanup_is_scoped(self, run):
        run.side_effect = [mock.Mock(stdout="41001\n"), mock.Mock(stdout="41002\n"), mock.Mock(), mock.Mock()]
        forwards = cli.setup_forwarding("test-serial")
        cli.remove_forwarding("test-serial", forwards)
        self.assertEqual(forwards, [41001, 41002])
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["adb", "-s", "test-serial", "forward", "tcp:0", "tcp:8022"],
            ["adb", "-s", "test-serial", "forward", "tcp:0", "tcp:8023"],
            ["adb", "-s", "test-serial", "forward", "--remove", "tcp:41001"],
            ["adb", "-s", "test-serial", "forward", "--remove", "tcp:41002"],
        ])


class TransportTests(unittest.TestCase):
    @mock.patch.object(cli.subprocess, "run")
    def test_probe_requires_successful_uid(self, run):
        run.return_value = mock.Mock(returncode=0, stdout="10234\n", stderr="")
        self.assertTrue(cli.supports_run_as("serial"))
        run.return_value = mock.Mock(returncode=1, stdout="", stderr="run-as: package not debuggable")
        self.assertFalse(cli.supports_run_as("serial"))
        for error in ("device offline", "package unknown", "permission denied"):
            run.return_value = mock.Mock(returncode=1, stdout="", stderr=error)
            with self.assertRaises(RuntimeError):
                cli.supports_run_as("serial")

    def invoke(self, arguments):
        with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", *arguments]):
            return cli.main()

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "run_as_shell", return_value=7)
    @mock.patch.object(cli, "supports_run_as", return_value=True)
    def test_auto_uses_run_as_without_forwarding(self, probe, shell, forward):
        self.assertEqual(self.invoke([]), 7)
        shell.assert_called_once_with("serial", cli.GUEST_LOGIN)
        forward.assert_not_called()

    @mock.patch.object(cli, "run_as_shell", return_value=0)
    @mock.patch.object(cli, "supports_run_as", return_value=True)
    def test_outer_uses_native_shell_for_command(self, probe, run):
        self.assertEqual(self.invoke(["--outer", "--", "true"]), 0)
        run.assert_called_once_with("serial", None, ["true"])

    @mock.patch.object(cli, "remove_forwarding")
    @mock.patch.object(cli, "run_shell")
    @mock.patch.object(cli, "setup_forwarding", return_value=[41001, 41002])
    @mock.patch.object(cli, "supports_run_as", return_value=False)
    def test_auto_falls_back_for_non_debuggable_app(self, probe, forward, shell, cleanup):
        self.assertEqual(self.invoke([]), 0)
        shell.assert_called_once()
        cleanup.assert_called_once_with("serial", [41001, 41002])

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "supports_run_as", side_effect=RuntimeError("offline"))
    def test_auto_does_not_hide_probe_failure(self, probe, forward):
        self.assertEqual(self.invoke([]), 1)
        forward.assert_not_called()

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "run_as_shell", side_effect=RuntimeError("launch failed"))
    @mock.patch.object(cli, "supports_run_as", return_value=True)
    def test_auto_does_not_fall_back_after_launch_failure(self, probe, shell, forward):
        self.assertEqual(self.invoke([]), 1)
        forward.assert_not_called()

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "supports_run_as", return_value=False)
    def test_explicit_run_as_does_not_fall_back(self, probe, forward):
        self.assertEqual(self.invoke(["--mode", "run-as"]), 1)
        forward.assert_not_called()

    @mock.patch.object(cli, "remove_forwarding")
    @mock.patch.object(cli, "run_shell")
    @mock.patch.object(cli, "setup_forwarding", return_value=[41001, 41002])
    @mock.patch.object(cli, "supports_run_as")
    def test_explicit_mtls_skips_probe(self, probe, forward, shell, cleanup):
        self.assertEqual(self.invoke(["--mode", "mtls"]), 0)
        probe.assert_not_called()
        shell.assert_called_once()

    @mock.patch.object(cli, "remove_forwarding")
    @mock.patch.object(cli, "create_credentials")
    @mock.patch.object(cli, "setup_forwarding", return_value=[41001, 41002])
    @mock.patch.object(cli, "supports_run_as")
    def test_auto_provision_uses_mtls(self, probe, forward, create, cleanup):
        self.assertEqual(self.invoke(["--provision"]), 0)
        probe.assert_not_called()
        create.assert_called_once()

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "supports_run_as")
    @mock.patch("builtins.print")
    def test_completions_do_not_require_serial_or_adb(self, output, probe, forward):
        for shell in ("bash", "zsh", "fish"):
            with mock.patch.object(cli.sys, "argv", ["cli", "--completions", shell]):
                self.assertEqual(cli.main(), 0)
            self.assertIn("termuxpp-adb-shell", output.call_args.args[0])
        probe.assert_not_called()
        forward.assert_not_called()

    def test_serial_still_required_for_device_operations(self):
        with mock.patch.object(cli.sys, "argv", ["cli"]), self.assertRaises(SystemExit) as error:
            cli.parse_args()
        self.assertEqual(error.exception.code, 2)

    def test_management_rejects_run_as(self):
        for option in ("--provision", "--list-authorizations", "--revoke"):
            args = [option, "a" * 64] if option == "--revoke" else [option]
            with self.assertRaises(SystemExit) as error:
                self.invoke(["--mode", "run-as", *args])
            self.assertEqual(error.exception.code, 2)

    @mock.patch.object(cli.sys.stdout, "isatty", return_value=True)
    @mock.patch.object(cli.sys.stdin, "isatty", return_value=True)
    @mock.patch.object(cli.subprocess, "run")
    def test_run_as_initializes_environment_and_returns_exit_status(self, run, stdin, stdout):
        run.side_effect = [mock.Mock(returncode=0, stdout="package:/data/app/random/base.apk\n"),
                           mock.Mock(returncode=7)]
        self.assertEqual(cli.run_as_shell("serial"), 7)
        self.assertEqual(run.call_args_list[0].kwargs["stdin"], subprocess.DEVNULL)
        self.assertNotIn("stdin", run.call_args.kwargs)
        command = run.call_args.args[0]
        self.assertEqual(command[:5], ["adb", "-s", "serial", "shell", "-tt"])
        remote = cli.shlex.split(command[5])
        self.assertEqual(remote[:4], ["run-as", cli.PACKAGE, "/system/bin/sh", "-c"])
        for value in ("TERMUX_APP__DATA_DIR", "LD_LIBRARY_PATH", "libtermux-pkg-redirect.so",
                      "/data/app/random/lib/*/", 'exec "$SHELL" -l', '"$HOME/.config/termuxpp/shell"'):
            self.assertIn(value, remote[4])


    @mock.patch.object(cli.subprocess, "run")
    def test_run_as_probe_cannot_consume_command_stdin(self, run):
        run.return_value = mock.Mock(returncode=0, stdout="10459\n")
        self.assertTrue(cli.supports_run_as("serial"))
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)


class AliasTests(unittest.TestCase):
    def invoke(self, arguments):
        with mock.patch.object(cli.sys, "argv", ["cli", *arguments]):
            return cli.main()

    def config(self, aliases):
        directory = cli.tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "devices.json"
        path.write_text(cli.json.dumps({"version": 1, "devices": aliases}))
        path.chmod(0o600)
        return path

    @mock.patch.object(cli, "run_as_shell", return_value=0)
    @mock.patch.object(cli, "supports_run_as", return_value=True)
    @mock.patch.object(cli.devices, "list_adb_devices", return_value=[("USB1", "device", {})])
    def test_alias_resolves_once_before_any_device_operation(self, listing, probe, shell):
        path = self.config({"one": {"serials": ["USB1", "WIFI1"]}})
        self.assertEqual(self.invoke(["--devices-config", str(path), "--serial", "one"]), 0)
        listing.assert_called_once()
        probe.assert_called_once_with("USB1")
        shell.assert_called_once_with("USB1", cli.GUEST_LOGIN)

    @mock.patch.object(cli, "setup_forwarding")
    @mock.patch.object(cli, "supports_run_as")
    @mock.patch.object(cli.devices, "list_adb_devices",
                       return_value=[("USB1", "device", {}), ("WIFI1", "device", {})])
    def test_ambiguous_alias_stops_before_touching_a_device(self, listing, probe, forward):
        path = self.config({"one": {"serials": ["USB1", "WIFI1"]}})
        self.assertEqual(self.invoke(["--devices-config", str(path), "--serial", "one"]), 1)
        probe.assert_not_called()
        forward.assert_not_called()

    @mock.patch.object(cli, "remove_forwarding")
    @mock.patch.object(cli, "create_credentials")
    @mock.patch.object(cli, "setup_forwarding", return_value=[41001, 41002])
    @mock.patch.object(cli.devices, "list_adb_devices", return_value=[("USB1", "device", {})])
    def test_alias_provision_targets_stable_credential_dir(self, listing, forward, create, cleanup):
        path = self.config({"one": {"serials": ["USB1"]}})
        self.assertEqual(self.invoke(["--devices-config", str(path), "--serial", "one", "--provision"]), 0)
        forward.assert_called_once_with("USB1")
        self.assertEqual(create.call_args.args[0], cli.DEFAULT_CREDENTIAL_DIR / "aliases" / "one")

    @mock.patch("builtins.print")
    def test_list_aliases_needs_no_serial_or_adb(self, output):
        path = self.config({"b": {"serials": ["x"]}, "a": {"serials": ["y"]}})
        with mock.patch.object(cli.devices, "list_adb_devices") as listing:
            self.assertEqual(self.invoke(["--devices-config", str(path), "--list-aliases"]), 0)
        listing.assert_not_called()
        output.assert_called_once_with("a\nb")


class RunAsShellSelectionTests(unittest.TestCase):
    def launcher(self, requested=None):
        with mock.patch.object(cli.sys.stdin, "isatty", return_value=True), \
                mock.patch.object(cli.sys.stdout, "isatty", return_value=True), \
                mock.patch.object(cli.subprocess, "run") as run:
            run.side_effect = [mock.Mock(returncode=0, stdout="package:/data/app/random/base.apk\n"),
                               mock.Mock(returncode=0)]
            cli.run_as_shell("serial", requested)
            script = cli.shlex.split(run.call_args.args[0][5])[4]
        return script[script.index("SHELL="):].replace("/system/bin/readlink", shutil.which("readlink"))

    def test_configured_shell_override_and_invalid_target(self):
        with cli.tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            prefix = Path(directory) / "usr"
            home.mkdir()
            (prefix / "bin").mkdir(parents=True)
            for shell in ("bash", "zsh", "fish"):
                executable = prefix / "bin" / shell
                executable.write_text(f'#!{shutil.which("sh")}\nprintf "%s:%s\\n" "$SHELL" "$1"\n')
                executable.chmod(0o700)
            environment = {**os.environ, "HOME": str(home), "PREFIX": str(prefix)}
            def launch(requested=None):
                return subprocess.run(["sh", "-c", self.launcher(requested)], env=environment,
                                      text=True, capture_output=True)
            self.assertEqual(launch().stdout.strip(), f"{prefix}/bin/bash:-l")
            config = home / ".config/termuxpp/shell"
            config.parent.mkdir(parents=True)
            config.symlink_to(prefix / "bin/zsh")
            self.assertEqual(launch().stdout.strip(), f"{prefix}/bin/zsh:-l")
            self.assertEqual(launch("fish").stdout.strip(), f"{prefix}/bin/fish:-l")
            self.assertNotEqual(launch("missing").returncode, 0)
            config.unlink()
            config.symlink_to(prefix / "bin/missing")
            self.assertNotEqual(launch().returncode, 0)


class SessionAuthenticationTests(unittest.TestCase):
    @mock.patch.object(cli, "request_token", side_effect=AssertionError("must not prompt"))
    @mock.patch.object(cli, "load_tls_credentials")
    @mock.patch.object(cli, "connect_tls")
    @mock.patch.object(cli, "read_line", return_value=b"OK")
    def test_certificate_session_does_not_request_token(self, line, connect, load, token):
        self.assertIs(cli.authenticated_connection(Path("credentials")), connect.return_value)
        connect.return_value.sendall.assert_called_once_with(b"TERMUXPP/2\n")
        token.assert_not_called()

    @mock.patch.object(cli, "load_tls_credentials")
    @mock.patch.object(cli, "connect_tls")
    @mock.patch.object(cli, "read_line", return_value=b"ERR")
    def test_old_server_fails_with_upgrade_message(self, line, connect, load):
        with self.assertRaisesRegex(RuntimeError, "update the TermuxPP app"):
            cli.authenticated_connection(Path("credentials"))
        connect.return_value.close.assert_called_once()


class ShellOptionTests(unittest.TestCase):
    def test_shell_option_rejects_protocol_injection_and_management(self):
        for value in ("zsh\nLIST", "zsh -c id", "", "é"):
            with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", "--shell", value]):
                with self.assertRaises(SystemExit):
                    cli.parse_args()
        with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", "--shell", "zsh", "--provision"]):
            with self.assertRaises(SystemExit):
                cli.parse_args()

    @mock.patch.object(cli, "supports_run_as", return_value=True)
    @mock.patch.object(cli, "run_as_shell", return_value=0)
    def test_override_reaches_run_as(self, shell, probe):
        with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", "--shell", "zsh"]):
            self.assertEqual(cli.main(), 0)
        shell.assert_called_once_with("serial", "zsh")

    @mock.patch.object(cli.sys.stdout, "isatty", return_value=True)
    @mock.patch.object(cli.sys.stdin, "isatty", return_value=True)
    @mock.patch.object(cli.termios, "tcgetattr")
    @mock.patch.object(cli.termios, "tcsetattr")
    @mock.patch.object(cli.tty, "setraw")
    @mock.patch.object(cli, "run_terminal")
    @mock.patch.object(cli, "read_line", return_value=b"OK")
    @mock.patch.object(cli, "authenticated_connection")
    def test_override_sent_as_executable_not_command(self, connect, line, terminal, raw, restore, state, stdin, stdout):
        cli.run_shell(Path("credentials"), "zsh")
        connect.return_value.sendall.assert_called_once_with(b"SHELL zsh\n")


class CommandTests(unittest.TestCase):
    def test_parser_keeps_command_arguments_literal(self):
        with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", "--shell", "zsh", "--",
                                                "printf", "%s", "two words", "$(id)", "--help", ""]):
            args = cli.parse_args()
        self.assertEqual(args.command, ["printf", "%s", "two words", "$(id)", "--help", ""])
        self.assertEqual(args.shell, "zsh")

    def test_management_and_oversized_commands_rejected(self):
        for options in (["--provision", "--", "id"], ["--", "echo", "a" * 65536]):
            with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", *options]):
                with self.assertRaises(SystemExit):
                    cli.parse_args()

    @mock.patch.object(cli.sys.stdin, "isatty", return_value=False)
    @mock.patch.object(cli.subprocess, "run")
    def test_run_as_command_does_not_require_tty_and_preserves_arguments(self, run, tty):
        run.side_effect = [mock.Mock(returncode=0, stdout="package:/data/app/test/base.apk\n"),
                           mock.Mock(returncode=7)]
        argv = ["printf", "%s", "two words", "$(id)", ""]
        self.assertEqual(cli.run_as_shell("serial", "zsh", argv), 7)
        remote = run.call_args.args[0]
        self.assertEqual(remote[:5], ["adb", "-s", "serial", "shell", "-T"])
        script = cli.shlex.split(remote[5])[4]
        suffix = next(line for line in script.splitlines() if line.startswith('  *) exec')).removeprefix('  *) ').removesuffix(' ;;')
        self.assertEqual(cli.shlex.split(suffix), ["exec", "$SHELL", "-l", "-c", 'exec "$@"',
                                                 "termuxpp-command", *argv])

    @mock.patch.object(cli, "supports_run_as", return_value=True)
    @mock.patch.object(cli, "run_as_shell", return_value=7)
    def test_main_returns_remote_command_exit(self, run, probe):
        with mock.patch.object(cli.sys, "argv", ["cli", "--serial", "serial", "--", "false"]):
            self.assertEqual(cli.main(), 7)
        run.assert_called_once_with("serial", cli.GUEST_LOGIN, ["false"])

    def test_mtls_streams_input_separates_output_and_returns_status(self):
        client, server = socket.socketpair()
        input_read, input_write = os.pipe()
        os.write(input_write, b"stdin payload")
        os.close(input_write)
        errors = []
        def serve():
            try:
                self.assertEqual(cli.receive_exact(server, 5), b"EXEC\n")
                size = int.from_bytes(cli.receive_exact(server, 4), "big")
                request = cli.json.loads(cli.receive_exact(server, size))
                self.assertEqual(request, {"shell": "zsh", "argv": ["printf", "two words", "$(id)"]})
                server.sendall(b"OK\n")
                received = b""
                while True:
                    kind = cli.receive_exact(server, 1)
                    size = int.from_bytes(cli.receive_exact(server, 4), "big")
                    chunk = cli.receive_exact(server, size)
                    if kind == b"E":
                        self.assertEqual(size, 0)
                        break
                    self.assertEqual(kind, b"I")
                    received += chunk
                self.assertEqual(received, b"stdin payload")
                for kind, data in ((b"O", b"stdout"), (b"R", b"stderr"), (b"X", (7).to_bytes(4, "big"))):
                    server.sendall(kind + len(data).to_bytes(4, "big") + data)
            except BaseException as error:
                errors.append(error)
            finally:
                server.close()
        thread = threading.Thread(target=serve)
        thread.start()
        stdout, stderr = mock.Mock(), mock.Mock()
        with os.fdopen(input_read, "rb") as stdin:
            with mock.patch.object(cli, "authenticated_connection", return_value=client), \
                    mock.patch.object(cli.sys, "stdin", stdin), \
                    mock.patch.object(cli.sys, "stdout", stdout), mock.patch.object(cli.sys, "stderr", stderr):
                self.assertEqual(cli.run_command(Path("unused"), "zsh", ["printf", "two words", "$(id)"]), 7)
        thread.join(5)
        self.assertFalse(thread.is_alive())
        if errors:
            raise errors[0]
        stdout.buffer.write.assert_called_once_with(b"stdout")
        stderr.buffer.write.assert_called_once_with(b"stderr")

    def test_mtls_rejects_invalid_response_frames(self):
        for kind, size in ((b"?", 0), (b"X", 3), (b"O", 65537)):
            client, server = socket.socketpair()
            server.sendall(b"OK\n" + kind + size.to_bytes(4, "big"))
            with mock.patch.object(cli, "authenticated_connection", return_value=client), \
                    mock.patch.object(cli.select, "select", return_value=([], [], [])):
                with self.assertRaisesRegex(RuntimeError, "invalid command response"):
                    cli.run_command(Path("unused"), None, ["id"])
            server.close()

    @mock.patch.object(cli.time, "sleep")
    @mock.patch.object(cli.socket, "create_connection", side_effect=cli.ssl.SSLEOFError())
    def test_unavailable_listener_has_actionable_error(self, connect, sleep):
        with self.assertRaisesRegex(RuntimeError, "mTLS listener is unavailable"):
            cli.connect_tls(mock.Mock())
        self.assertEqual(connect.call_count, 4)


class CompletionTests(unittest.TestCase):
    def completion_path(self, shell):
        return Path(cli.__file__).parent / "completions" / f"termuxpp-adb-shell.{shell}"

    @unittest.skipUnless(shutil.which("bash"), "bash not installed")
    def test_bash_completes_modes_and_only_authorized_devices(self):
        script = r'''
source "$1"
adb() { printf 'List of devices attached\nready device\nlocked unauthorized\noff offline\n'; }
COMP_WORDS=(termuxpp-adb-shell --mode r)
COMP_CWORD=2
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == run-as ]] || exit 1
COMP_WORDS=(termuxpp-adb-shell --shell z)
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == zsh ]] || exit 1
COMP_WORDS=(termuxpp-adb-shell.py --serial '')
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == ready ]]
'''
        subprocess.run(["bash", "-c", script, "test", str(self.completion_path("bash"))], check=True)

    @unittest.skipUnless(shutil.which("bash"), "bash not installed")
    def test_bash_completes_aliases_from_the_cli(self):
        script = r'''
source "$1"
adb() { printf 'List of devices attached\nready device\n'; }
termuxpp-adb-shell() { [[ "$1" == --list-aliases ]] && printf 'alpha\nbeta\n'; }
COMP_WORDS=(termuxpp-adb-shell --serial '')
COMP_CWORD=2
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == "ready alpha beta" ]] || exit 1
COMP_WORDS=(termuxpp-adb-shell --serial a)
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == alpha ]]
'''
        subprocess.run(["bash", "-c", script, "test", str(self.completion_path("bash"))], check=True)

    @unittest.skipUnless(shutil.which("zsh"), "zsh not installed")
    def test_zsh_completes_aliases_from_the_cli(self):
        script = r'''
source "$1"
adb() { printf 'List of devices attached\nready device\n'; }
termuxpp-adb-shell() { printf 'alpha\nbeta\n'; }
words=(termuxpp-adb-shell --serial '')
compadd() { shift; print -r -- "$*"; }
[[ "$(_termuxpp_adb_shell_serials)" == 'ready alpha beta' ]]
'''
        subprocess.run(["zsh", "-fc", script, "test", str(self.completion_path("zsh"))], check=True)

    @unittest.skipUnless(shutil.which("zsh"), "zsh not installed")
    def test_zsh_registers_both_commands_and_completes_devices(self):
        script = r'''
autoload -Uz compinit
compinit -D
source "$1"
[[ ${_comps[termuxpp-adb-shell]} == _termuxpp_adb_shell ]] || exit 1
[[ ${_comps[termuxpp-adb-shell.py]} == _termuxpp_adb_shell ]] || exit 1
adb() { printf 'List of devices attached\nready device\nlocked unauthorized\noff offline\n'; }
compadd() { shift; [[ "$*" == ready ]]; }
_termuxpp_adb_shell_serials
'''
        subprocess.run(["zsh", "-fc", script, "test", str(self.completion_path("zsh"))], check=True)

    @unittest.skipUnless(shutil.which("zsh"), "zsh not installed")
    def test_zsh_native_autoload_completes_on_first_call(self):
        script = r'''
autoload -Uz compinit
compinit -D
fpath=("$1" $fpath)
_arguments() { called=1; }
autoload -Uz _termuxpp-adb-shell
_termuxpp-adb-shell
[[ $called == 1 ]]
'''
        with cli.tempfile.TemporaryDirectory() as directory:
            shutil.copyfile(self.completion_path("zsh"), Path(directory) / "_termuxpp-adb-shell")
            subprocess.run(["zsh", "-fc", script, "test", directory], check=True)

    @unittest.skipUnless(shutil.which("bash"), "bash not installed")
    def test_bash_completes_command_after_separator(self):
        script = r'''
source "$1"
termuxpp_completion_probe() { :; }
COMP_WORDS=(termuxpp-adb-shell --shell zsh -- termuxpp_completion_pr)
COMP_CWORD=4
_termuxpp_adb_shell
[[ " ${COMPREPLY[*]} " == *' termuxpp_completion_probe '* ]]
'''
        subprocess.run(["bash", "-c", script, "test", str(self.completion_path("bash"))], check=True)

    @unittest.skipUnless(shutil.which("fish"), "fish not installed")
    def test_fish_completes_command_not_wrapper_options_after_separator(self):
        script = r'''
source $argv[1]
function termuxpp_completion_probe
end
complete -C 'termuxpp-adb-shell -- termuxpp_completion_pr' | string match -q 'termuxpp_completion_probe*'; or exit 1
set -l matches (complete -C 'termuxpp-adb-shell -- printf --mo')
not string match -q -- '--mode*' $matches
'''
        subprocess.run(["fish", "-c", script, str(self.completion_path("fish"))], check=True)

    @unittest.skipUnless(shutil.which("fish"), "fish not installed")
    def test_fish_completion_syntax(self):
        subprocess.run(["fish", "--no-execute", str(self.completion_path("fish"))], check=True)


if __name__ == "__main__":
    unittest.main()
