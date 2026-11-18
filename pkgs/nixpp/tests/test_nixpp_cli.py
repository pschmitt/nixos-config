#!/usr/bin/env python3
"""Black-box checks for the compiled guest manager; pass its executable path."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve())


class NixppCliTest(unittest.TestCase):
    def run_cli(self, *arguments, **environment):
        env = os.environ.copy()
        env.update(environment)
        return subprocess.run([BINARY, *arguments], env=env, capture_output=True,
                              text=True, timeout=10)

    def test_help_is_plain_when_redirected(self):
        result = self.run_cli('--help', NO_COLOR='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\x1b', result.stdout + result.stderr)
        for command in ('prepare', 'rebuild', 'recover', 'rollback', 'serve'):
            self.assertIn(command, result.stdout)

    def test_invalid_candidate_is_rejected_before_connecting(self):
        for candidate in ('../escape', '/absolute', 'short', 'x' * 32 + '-bad/name'):
            with self.subTest(candidate=candidate):
                result = self.run_cli('switch', candidate,
                                      NIXPP_SOCKET='/definitely/not/a/socket')
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('No such file', result.stderr)

    def test_build_rejects_output_fragment(self):
        result = self.run_cli('build', '--flake', 'path:/config#unexpected',
                              '--host', 'guest-test')
        self.assertNotEqual(result.returncode, 0)

    def test_serve_rejects_writable_socket_directory(self):
        with tempfile.TemporaryDirectory(prefix='nixpp-serve-') as directory:
            runtime = Path(directory) / 'runtime'
            runtime.mkdir(mode=0o700)
            public = Path(directory) / 'public'
            public.mkdir()
            public.chmod(0o777)
            result = self.run_cli('--runtime', str(runtime), 'serve', '--socket',
                                  str(public / 'control.sock'))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((public / 'control.sock').exists())

    def with_response(self, response):
        with tempfile.TemporaryDirectory(prefix='nixpp-cli-') as directory:
            path = str(Path(directory) / 'control.sock')
            received = []
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(path)
                server.listen(1)
                server.settimeout(5)

                def answer():
                    connection, _ = server.accept()
                    with connection:
                        connection.settimeout(5)
                        received.append(connection.recv(8192))
                        connection.sendall(response)

                thread = threading.Thread(target=answer, daemon=True)
                thread.start()
                result = self.run_cli('--json', 'list-generations', NIXPP_SOCKET=path)
                thread.join(timeout=6)
                self.assertFalse(thread.is_alive(), 'client did not finish the request')
            self.assertTrue(received)
            self.assertEqual(json.loads(received[0])['command'], 'list-generations')
            return result

    def test_json_has_no_ansi(self):
        result = self.with_response(b'{"status":0,"generations":[]}\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        self.assertIsNotNone(json.loads(result.stdout))

    def test_native_failure_is_not_success(self):
        result = self.with_response(b'{"status":1,"error":"fixture activation failed"}\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fixture activation failed', result.stderr)

    def test_invalid_native_status_is_rejected(self):
        for response in (b'{"status":true,"generations":[]}\n',
                         b'{"generations":[]}\n', b'not json\n'):
            with self.subTest(response=response):
                self.assertNotEqual(self.with_response(response).returncode, 0)

    def test_oversized_native_response_is_rejected(self):
        result = self.with_response(b' ' * 65537 + b'\n')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
