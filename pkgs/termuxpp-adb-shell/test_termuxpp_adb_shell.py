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
        shell.assert_called_once_with("serial")
        forward.assert_not_called()

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
        command = run.call_args.args[0]
        self.assertEqual(command[:5], ["adb", "-s", "serial", "shell", "-tt"])
        remote = cli.shlex.split(command[5])
        self.assertEqual(remote[:4], ["run-as", cli.PACKAGE, "/system/bin/sh", "-c"])
        for value in ("TERMUX_APP__DATA_DIR", "LD_LIBRARY_PATH", "libtermux-pkg-redirect.so",
                      "/data/app/random/lib/*/", 'exec "$PREFIX/bin/bash" -l'):
            self.assertIn(value, remote[4])


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
COMP_WORDS=(termuxpp-adb-shell.py --serial '')
_termuxpp_adb_shell
[[ "${COMPREPLY[*]}" == ready ]]
'''
        subprocess.run(["bash", "-c", script, "test", str(self.completion_path("bash"))], check=True)

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

    @unittest.skipUnless(shutil.which("fish"), "fish not installed")
    def test_fish_completion_syntax(self):
        subprocess.run(["fish", "--no-execute", str(self.completion_path("fish"))], check=True)


if __name__ == "__main__":
    unittest.main()
