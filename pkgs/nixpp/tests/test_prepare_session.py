#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('prepare_system', Path(__file__).with_name('prepare-session.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.runtime = root / 'runtime'
        self.generation = root / ('a' * 32 + '-termuxpp-system-test')
        for path in [self.runtime / 'root/etc', self.generation / 'etc/nested',
                     self.generation / 'sw/bin', self.generation / 'terminfo']:
            path.mkdir(parents=True)
        (self.runtime / 'session.json').write_text(json.dumps({
            'schema': 1, 'system': 'aarch64-linux', 'pageSize': 4096}))
        (self.runtime / 'root/etc/passwd').write_text('guest:x:123:456:Guest:/home/guest:/bin/sh\n')
        (self.runtime / 'root/etc/group').write_text('guest:x:456:\n')
        (self.runtime / 'root/etc/resolv.conf').write_text('nameserver 127.0.0.1\n')
        (self.runtime / 'root/etc/example').write_text('old\n')
        (self.generation / 'etc/example').write_text('new\n')
        (self.generation / 'etc/nested/value').write_text('nested\n')
        (self.generation / 'shell').touch()
        (self.generation / 'cert').touch()
        self.data = {
            'formatVersion': 1, 'stateVersion': '1', 'runtime': 'droid-nix',
            'name': 'guest', 'home': '/home/guest', 'homeManager': None,
            'systemPath': str(self.generation / 'sw'),
            'session': {key: str(self.generation / filename) for key, filename in
                        [('shell', 'shell'), ('certificate', 'cert'), ('terminfo', 'terminfo')]},
        }
        self.save()

    def save(self):
        (self.generation / 'manifest.json').write_text(json.dumps(self.data))

    def prepare(self):
        # Temporary fixtures stand in for store paths; validate the real grammar separately.
        with patch.object(module, 'store_path', side_effect=lambda value: value):
            return module.prepare(self.runtime, self.generation)

    def test_prepare_retains_base_and_overlays_system(self):
        result = self.prepare()
        self.assertEqual((result / 'etc/example').read_text(), 'new\n')
        self.assertEqual((result / 'etc/nested/value').read_text(), 'nested\n')
        self.assertEqual((result / 'etc/resolv.conf').read_text(), 'nameserver 127.0.0.1\n')
        self.assertEqual((self.runtime / 'root/etc/example').read_text(), 'old\n')
        self.assertEqual((result / 'etc/passwd').read_bytes(), (self.runtime / 'root/etc/passwd').read_bytes())
        self.assertEqual(len((result / 'session').read_text().splitlines()), 6)
        self.assertEqual(result.stat().st_mode & 0o777, 0o700)
        self.assertEqual((result / 'etc/example').stat().st_mode & 0o777, 0o600)
        gcroot = self.runtime / 'root/nix/var/nix/gcroots/termuxpp-system-candidates' / self.generation.name
        self.assertEqual(gcroot.readlink(), self.generation)
        self.assertFalse((self.runtime / 'current-system').exists())

    def test_retained_candidate_is_not_overwritten(self):
        candidate = self.prepare()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        self.assertTrue((candidate / 'session').is_file())

    def test_identity_mismatch(self):
        self.data['name'] = 'other'
        self.data['home'] = '/home/other'
        self.save()
        with self.assertRaisesRegex(ValueError, 'identity does not match'):
            self.prepare()

    def test_unsupported_schema(self):
        self.data['formatVersion'] = 2
        self.save()
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            self.prepare()

    def test_reserved_identity_files(self):
        (self.generation / 'etc/passwd').write_text('not Android\n')
        with self.assertRaisesRegex(ValueError, 'passwd/group'):
            self.prepare()

    def test_missing_closure(self):
        (self.generation / 'shell').unlink()
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.prepare()

    def test_failed_copy_leaves_no_candidate(self):
        (self.generation / 'etc/cycle').symlink_to(self.generation / 'etc', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'directory symlinks'):
            self.prepare()
        self.assertEqual(list((self.runtime / 'system-candidates').iterdir()), [])

    def test_configuration_file_links_are_materialized(self):
        (self.generation / 'etc/linked').symlink_to(self.generation / 'etc/example')
        result = self.prepare()
        self.assertFalse((result / 'etc/linked').is_symlink())
        self.assertEqual((result / 'etc/linked').read_text(), 'new\n')

    def test_store_path_validation(self):
        good = '/nix/store/' + 'a' * 32 + '-bash/bin/bash'
        self.assertEqual(module.store_path(good), good)
        for value in [None, '/bin/bash', good + '/../escape', good + ':bad', good + '\nextra']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.store_path(value)


class ManagementTests(unittest.TestCase):
    def test_build_never_compiles_on_phone(self):
        path = '/nix/store/' + 'a' * 32 + '-termuxpp-system-test'
        runner = Mock(return_value=Mock(stdout=path + '\n'))
        self.assertEqual(module.build_system('/source', 'test', run=runner), Path(path))
        command = runner.call_args.args[0]
        self.assertEqual(command, ['nix', 'build', '--max-jobs', '0', '--no-link',
                                   '--print-out-paths', '/source#termuxppConfigurations.test.system'])
        self.assertTrue(runner.call_args.kwargs['check'])

    def test_build_uses_existing_rworker_integration(self):
        path = '/nix/store/' + 'a' * 32 + '-termuxpp-system-test'
        runner = Mock(return_value=Mock(stdout=path + '\n'))
        module.build_system('github:example/config', 'test', rworker=True, run=runner)
        self.assertEqual(runner.call_args.args[0][:2], ['rworker-nix', 'build'])

    def test_invalid_build_arguments_never_launch(self):
        runner = Mock()
        for flake, host in [('--bad', 'host'), ('source#other', 'host'), ('source', 'host.bad'), ('', 'host')]:
            with self.subTest(flake=flake, host=host), self.assertRaises(ValueError):
                module.build_system(flake, host, run=runner)
        runner.assert_not_called()

    def test_build_output_is_validated(self):
        for output in ['', '/tmp/not-store\n', '/nix/store/' + 'a' * 32 + '-one\n/nix/store/' + 'b' * 32 + '-two\n']:
            with self.subTest(output=output), self.assertRaises(ValueError):
                module.build_system('source', 'host', run=Mock(return_value=Mock(stdout=output)))

    def test_native_management_protocol_is_data_only(self):
        client = Mock()
        client.recv.return_value = b'{"status":0,"generations":[]}\n'
        context = Mock()
        context.__enter__ = Mock(return_value=client)
        context.__exit__ = Mock(return_value=False)
        with patch.object(module.socket, 'socket', return_value=context):
            self.assertEqual(module.manage('list-generations', socket_path='/tmp/test.sock')['generations'], [])
        client.connect.assert_called_once_with('/tmp/test.sock')
        self.assertEqual(json.loads(client.sendall.call_args.args[0]), {'command': 'list-generations'})

    def test_invalid_candidate_never_connects(self):
        with patch.object(module.socket, 'socket') as socket:
            with self.assertRaises(ValueError):
                module.manage('switch', '../escape')
            socket.assert_not_called()


if __name__ == '__main__':
    unittest.main()
