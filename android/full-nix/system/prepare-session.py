#!/usr/bin/env python3
"""Prepare a candidate guest system session; never activate Home Manager or select it."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
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


def manage(command, candidate=None, socket_path=None):
    request = {'command': command}
    if candidate is not None:
        if not re.fullmatch(r'[a-z0-9]{32}-[a-zA-Z0-9+._-]+', candidate):
            raise ValueError('invalid system candidate name')
        request['candidate'] = candidate
    path = socket_path or os.environ.get('NIXPP_SOCKET', '/tmp/nixpp.sock')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(4500)
        connection.connect(path)
        connection.sendall(json.dumps(request).encode() + b'\n')
        payload = bytearray()
        while not payload.endswith(b'\n'):
            chunk = connection.recv(65537 - len(payload))
            if not chunk or len(payload) + len(chunk) > 65536:
                raise ValueError('invalid native controller response')
            payload.extend(chunk)
    response = json.loads(payload)
    if not isinstance(response, dict) or type(response.get('status')) is not int:
        raise ValueError('invalid native controller status')
    if response['status']:
        raise ValueError(response.get('error', f'native controller failed with status {response["status"]}'))
    return response


def build_system(flake, host, rworker=False, run=subprocess.run):
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', host):
        raise ValueError('invalid system host name')
    if not flake or flake.startswith('-') or '#' in flake:
        raise ValueError('supply a flake URI without an output fragment')
    target = f'{flake}#termuxppConfigurations.{host}.system'
    command = ['rworker-nix', 'build'] if rworker else ['nix', 'build', '--max-jobs', '0']
    result = run([*command, '--no-link', '--print-out-paths', target],
                 check=True, stdout=subprocess.PIPE, text=True)
    paths = result.stdout.splitlines()
    if len(paths) != 1:
        raise ValueError('build did not return exactly one system generation')
    return Path(store_path(paths[0]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    candidate = commands.add_parser('prepare', help='prepare a candidate without selecting or activating it')
    candidate.add_argument('--runtime', required=True, type=Path,
                           help='native runtime directory exposed through /android')
    candidate.add_argument('generation', type=Path)
    for name in ('build', 'rebuild'):
        build = commands.add_parser(name, help='build a system remotely' if name == 'build' else 'build, prepare and switch a system')
        build.add_argument('--flake', required=True)
        build.add_argument('--host', required=True)
        build.add_argument('--rworker', action='store_true', help='use the configured disposable-worker builder')
        if name == 'rebuild':
            build.add_argument('--runtime', type=Path, default=os.environ.get('NIXPP_RUNTIME'))
    for name in ('switch', 'check'):
        command = commands.add_parser(name, help=f'{name} a prepared system through the native controller')
        command.add_argument('candidate')
    for name in ('list-generations', 'rollback', 'recover'):
        commands.add_parser(name, help=f'{name} through the native controller')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == 'prepare':
            print(prepare(args.runtime, args.generation))
        elif args.command in ('build', 'rebuild'):
            if args.command == 'rebuild' and args.runtime is None:
                raise ValueError('rebuild requires NIXPP_RUNTIME or --runtime')
            generation = build_system(args.flake, args.host, args.rworker)
            if args.command == 'build':
                print(generation)
            else:
                runtime = Path(args.runtime)
                destination = runtime / 'system-candidates' / generation.name
                if not destination.exists():
                    prepare(runtime, generation)
                manage('switch', generation.name)
                print(generation)
        else:
            response = manage(args.command, getattr(args, 'candidate', None))
            if args.command == 'list-generations':
                print(json.dumps(response['generations'], sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'nixpp: {error}\n')


if __name__ == '__main__':
    main()
