import base64
import hashlib
import hmac
import importlib.util
import os
from pathlib import Path
import socket
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


if __name__ == "__main__":
    unittest.main()
