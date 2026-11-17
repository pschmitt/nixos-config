#!/usr/bin/env python3
"""Prepare a candidate guest system session; never activate Home Manager or select it."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

STORE = re.compile(r'/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+._-]+(?:/[a-zA-Z0-9+._-]+)*')


def store_path(value):
    if not isinstance(value, str) or not STORE.fullmatch(value) or '..' in value.split('/'):
        raise ValueError('invalid guest store path')
    return value


def copy_tree(source, target):
    for entry in sorted(source.iterdir()):
        destination = target / entry.name
        if entry.is_dir():
            if entry.is_symlink():
                raise ValueError('configuration directory symlinks are not supported')
            if destination.exists() and not destination.is_dir():
                raise ValueError('configuration directory conflicts with an existing file')
            destination.mkdir(mode=0o700, exist_ok=True)
            copy_tree(entry, destination)
        elif entry.is_file():
            if destination.is_dir():
                raise ValueError('configuration file conflicts with an existing directory')
            shutil.copyfile(entry, destination)
            destination.chmod(0o600)
        else:
            raise ValueError('configuration contains a special or dangling file')


def prepare(runtime, generation):
    runtime = runtime.resolve(strict=True)
    generation = generation.resolve(strict=True)
    store_path(str(generation))
    data = json.loads((generation / 'manifest.json').read_text())
    if data.get('formatVersion') != 1 or data.get('stateVersion') != '1' or data.get('runtime') != 'droid-nix':
        raise ValueError('unsupported guest system manifest')
    user = data.get('name')
    if not isinstance(user, str) or not re.fullmatch(r'[a-z_][a-z0-9_-]*', user) or data.get('home') != f'/home/{user}':
        raise ValueError('invalid guest identity')
    for entry in ('passwd', 'group'):
        if (generation / 'etc' / entry).exists() or (generation / 'etc' / entry).is_symlink():
            raise ValueError('Android-owned passwd/group cannot be overridden by a candidate')
    base = json.loads((runtime / 'session.json').read_text())
    if base.get('schema') != 1 or base.get('system') != 'aarch64-linux' or base.get('pageSize') != 4096:
        raise ValueError('unsupported base runtime')
    passwd = (runtime / 'root/etc/passwd').read_text().splitlines()
    records = [line.split(':') for line in passwd if line.split(':')[0] == user]
    if len(records) != 1 or len(records[0]) != 7 or records[0][5] != data['home']:
        raise ValueError('candidate identity does not match the prepared runtime')
    session = data.get('session', {})
    values = [user, data['home'], store_path(data['systemPath']) + '/bin',
              store_path(session.get('shell')), store_path(session.get('certificate')),
              store_path(session.get('terminfo'))]
    if any(not Path(path).exists() for path in values[2:]):
        raise ValueError('candidate closure is not fully available')
    home = data.get('homeManager')
    if home is not None and not (Path(store_path(home)) / 'activate').is_file():
        raise ValueError('associated Home Manager generation is unavailable')
    candidates = runtime / 'system-candidates'
    if candidates.is_symlink():
        raise ValueError('candidate directory must not be a symlink')
    candidates.mkdir(mode=0o700, exist_ok=True)
    name = generation.name
    destination = candidates / name
    if destination.exists() or destination.is_symlink():
        raise ValueError('candidate already exists; retained candidates are never overwritten')
    stage = Path(tempfile.mkdtemp(prefix='.prepare-', dir=candidates))
    try:
        etc = stage / 'etc'
        etc.mkdir(mode=0o700)
        copy_tree(runtime / 'root/etc', etc)
        copy_tree(generation / 'etc', etc)
        # Android owns numeric credentials; a generation may not replace them.
        for entry in ('passwd', 'group'):
            shutil.copyfile(runtime / 'root/etc' / entry, etc / entry)
            (etc / entry).chmod(0o600)
        (stage / 'session').write_text('\n'.join(values) + '\n')
        (stage / 'generation').write_text(str(generation) + '\n')
        (stage / 'manifest.json').write_text(json.dumps(data, sort_keys=True) + '\n')
        roots = runtime / 'root/nix/var/nix/gcroots/termuxpp-system-candidates'
        if roots.is_symlink():
            raise ValueError('candidate GC root directory must not be a symlink')
        roots.mkdir(mode=0o700, parents=True, exist_ok=True)
        root = roots / name
        root.symlink_to(generation)
        try:
            os.rename(stage, destination)
        except BaseException:
            root.unlink()
            raise
    except BaseException:
        shutil.rmtree(stage)
        raise
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    candidate = commands.add_parser('prepare', help='prepare a candidate without selecting or activating it')
    candidate.add_argument('--runtime', required=True, type=Path,
                           help='native runtime directory exposed through /android')
    candidate.add_argument('generation', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        print(prepare(args.runtime, args.generation))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Cannot prepare system candidate: {error}\n')


if __name__ == '__main__':
    main()
