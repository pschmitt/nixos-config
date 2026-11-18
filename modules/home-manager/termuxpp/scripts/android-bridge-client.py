#!/usr/bin/env python3
"""Ask the native Android bridge broker for an allowlisted Android action.

This runs inside the Linux/glibc full-Nix guest, which cannot execute Bionic
helpers. The broker is started separately from the native TermuxPP shell.
"""
import argparse
import errno
import json
import os
import socket
import sys

PROTOCOL = 1
MAX_RESPONSE = 65536
DEFAULT_SOCKET = '/tmp/android-bridge/bridge.sock'
EX_USAGE = 2
EX_UNAVAILABLE = 69
EX_PROTOCOL = 76
EX_SOFTWARE = 70
START_HINT = (
    'Start the broker from the native TermuxPP shell (outside the guest):\n'
    '  R="$HOME/.local/share/termuxpp-nix"\n'
    '  /system/bin/sh "$R/start-android-bridge.sh"'
)


class Unavailable(Exception):
    pass


def connect(path, timeout):
    """Connect to path; retry via a relative name when a translated path is too long."""
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        try:
            client.connect(path)
        except OSError as error:
            if error.errno != errno.ENAMETOOLONG:
                raise
            directory, name = os.path.split(path)
            old = os.open('.', os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.chdir(directory)
                client.connect(name)
            finally:
                os.fchdir(old)
                os.close(old)
    except OSError:
        client.close()
        raise
    return client


def request(path, command, args, timeout):
    payload = json.dumps({'v': PROTOCOL, 'command': command, 'args': args}, separators=(',', ':'))
    try:
        client = connect(path, timeout)
    except (FileNotFoundError, ConnectionRefusedError) as error:
        raise Unavailable(
            f'Android bridge broker is not running (socket {path}: {error.strerror}).\n{START_HINT}'
        ) from error
    except PermissionError as error:
        raise Unavailable(f'Cannot access the Android bridge socket {path}: {error.strerror}') from error
    except OSError as error:
        raise Unavailable(f'Cannot connect to the Android bridge socket {path}: {error.strerror}') from error
    with client:
        try:
            client.sendall(payload.encode() + b'\n')
            client.shutdown(socket.SHUT_WR)
            data = bytearray()
            while len(data) <= MAX_RESPONSE:
                chunk = client.recv(4096)
                if not chunk:
                    break
                data.extend(chunk)
        except OSError as error:
            raise Unavailable(f'Android bridge connection failed: {error}') from error
    if len(data) > MAX_RESPONSE:
        raise ValueError('response too large')
    response = json.loads(data.decode('utf-8'))
    if not isinstance(response, dict) or not isinstance(response.get('ok'), bool):
        raise ValueError('malformed response')
    return response


def parser():
    argp = argparse.ArgumentParser(description=__doc__)
    argp.add_argument('--socket', default=os.environ.get('ANDROID_BRIDGE_SOCKET', DEFAULT_SOCKET),
                      help='broker socket (default: $ANDROID_BRIDGE_SOCKET or %(default)s)')
    argp.add_argument('--timeout', type=float, default=40.0, help='seconds to wait for the broker')
    commands = argp.add_subparsers(dest='command', required=True)
    commands.add_parser('ping', help='check the broker answers (no side effects)')
    commands.add_parser('status', help='show broker limits and helper availability (no side effects)')
    commands.add_parser('battery-status', help='print battery status as JSON')
    toast = commands.add_parser('toast', help='show an Android toast')
    toast.add_argument('-s', '--short', action='store_true', help='short duration')
    toast.add_argument('-g', '--gravity', choices=('top', 'middle', 'bottom'))
    toast.add_argument('-b', '--background', metavar='#RRGGBB')
    toast.add_argument('-c', '--color', metavar='#RRGGBB')
    toast.add_argument('text', nargs='+', help='toast text')
    return argp


def build_args(namespace):
    if namespace.command != 'toast':
        return {}
    args = {'text': ' '.join(namespace.text)}
    if namespace.short:
        args['short'] = True
    for key in ('gravity', 'background', 'color'):
        if getattr(namespace, key) is not None:
            args[key] = getattr(namespace, key)
    return args


def main(argv=None):
    namespace = parser().parse_args(argv)
    try:
        response = request(namespace.socket, namespace.command, build_args(namespace), namespace.timeout)
    except Unavailable as error:
        print(f'android-bridge: {error}', file=sys.stderr)
        return EX_UNAVAILABLE
    except ValueError as error:
        print(f'android-bridge: protocol error: {error}', file=sys.stderr)
        return EX_PROTOCOL
    if response['ok']:
        print(json.dumps(response.get('result'), indent=2, sort_keys=True))
        return 0
    error = response.get('error') or {}
    print(f'android-bridge: {error.get("code", "error")}: {error.get("message", "request failed")}',
          file=sys.stderr)
    return EX_SOFTWARE


if __name__ == '__main__':
    sys.exit(main())
