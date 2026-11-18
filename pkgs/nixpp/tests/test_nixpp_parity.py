#!/usr/bin/env python3
"""Compare candidate preparation artifacts using real Nix-built store fixtures."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def runtime_fixture(path, identity='guest', page_size=4096):
    (path / 'root/etc').mkdir(parents=True, mode=0o700)
    (path / 'session.json').write_text(json.dumps({
        'schema': 1, 'system': 'aarch64-linux', 'pageSize': page_size}))
    (path / 'root/etc/passwd').write_text(
        f'{identity}:x:123:456:Guest:/home/{identity}:/bin/sh\n')
    (path / 'root/etc/group').write_text(f'{identity}:x:456:\n')
    (path / 'root/etc/resolv.conf').write_text('nameserver 127.0.0.1\n')


def snapshot(runtime):
    result = {}
    for relative in ('system-candidates', 'root/nix/var/nix/gcroots/termuxpp-system-candidates'):
        directory = runtime / relative
        if not directory.exists():
            continue
        for path in sorted(directory.rglob('*')):
            name = str(path.relative_to(runtime))
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                result[name] = ('link', str(path.readlink()))
            elif stat.S_ISDIR(info.st_mode):
                result[name] = ('directory', stat.S_IMODE(info.st_mode))
            elif stat.S_ISREG(info.st_mode):
                result[name] = ('file', stat.S_IMODE(info.st_mode), path.read_bytes())
            else:
                raise AssertionError(f'unexpected special file: {name}')
    result['selected'] = (runtime / 'current-system').exists()
    return result


def compare(reference, binary, generation, *, duplicate=False, identity='guest', page_size=4096):
    with tempfile.TemporaryDirectory(prefix='nixpp-parity-') as temporary:
        root = Path(temporary)
        old, new = root / 'reference', root / 'rust'
        for runtime in (old, new):
            runtime_fixture(runtime, identity, page_size)
        commands = (
            [sys.executable, '-I', reference, 'prepare', '--runtime', str(old), generation],
            [binary, 'prepare', '--runtime', str(new), generation],
        )
        if duplicate:
            for command in commands:
                first = subprocess.run(command, capture_output=True, text=True, timeout=30)
                assert first.returncode == 0, first.stderr
        results = [subprocess.run(command, capture_output=True, text=True, timeout=30)
                   for command in commands]
        expected_success = not duplicate and identity == 'guest' and page_size == 4096
        for result in results:
            assert (result.returncode == 0) == expected_success, result.stderr
        before, after = snapshot(old), snapshot(new)
        assert before == after, (
            f'artifact mismatch: only reference={before.keys() - after.keys()}, '
            f'only Rust={after.keys() - before.keys()}, '
            f'changed={[key for key in before.keys() & after.keys() if before[key] != after[key]]}')


def main():
    reference, binary, plain, integrated = sys.argv[1:]
    cases = (
        ('plain system', plain, {}),
        ('Home Manager system', integrated, {}),
        ('retained candidate', plain, {'duplicate': True}),
        ('identity mismatch', plain, {'identity': 'other'}),
        ('incompatible runtime', plain, {'page_size': 16384}),
    )
    for name, generation, options in cases:
        compare(reference, binary, generation, **options)
        print(f'prepare parity: {name}: matched')
    print(f'prepare parity: {len(cases)} fixture classes compared, 0 differences')


if __name__ == '__main__':
    main()
