#!/usr/bin/env python3
"""SSH ProxyCommand that tunnels to a TermuxPP SSH daemon over ADB (adb shell toybox nc).

Example ~/.ssh/config entry (SERIAL may be a configured device alias):

    Host phone
      ProxyCommand termuxpp-adb-ssh-proxy --serial SERIAL
"""

import argparse
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import termuxpp_adb_devices as devices

CLI = Path(__file__).resolve().with_name("termuxpp-adb-shell.py")


class ProbeError(RuntimeError):
    """The listener state could not be determined."""


def seconds(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number of seconds")
    return value


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial", required=True, help="ADB serial or configured device alias")
    parser.add_argument("--devices-config", type=Path, help="private JSON device alias configuration")
    parser.add_argument("--port", type=int, help="device-side SSH port (default: alias ssh.port, else 2222)")
    parser.add_argument("--credential-dir", type=Path, help="mTLS credential directory used to start the daemon")
    parser.add_argument("--no-start", action="store_true", help="never try to start the daemon")
    parser.add_argument("--probe-timeout", type=seconds, default=8, help="seconds for one listener probe (default: 8)")
    parser.add_argument("--start-timeout", type=seconds, default=20,
                        help="total seconds the start command may run (default: 20)")
    parser.add_argument("--ready-timeout", type=seconds, default=30,
                        help="seconds to wait for the listener after starting it (default: 30)")
    args = parser.parse_args(argv)
    if args.port is not None and not 1 <= args.port <= 65535:
        parser.error("--port must be a TCP port number")
    return args


def probe_listener(serial, port, timeout):
    """True if the listener accepts a connection, False only if it refuses; ProbeError otherwise.

    stdin is detached so the SSH stream is never consumed.
    """
    command = ["adb", "-s", serial, "shell", "-T", "toybox", "nc", "-w", "2", "127.0.0.1", str(port)]
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ProbeError("listener probe timed out") from None
    except FileNotFoundError:
        raise ProbeError("adb is not installed") from None
    if result.returncode == 0 or result.stdout.startswith(b"SSH-"):
        return True
    if b"connection refused" in result.stderr.lower():
        return False
    raise ProbeError("listener probe failed: " + (result.stderr.decode("utf-8", "replace").strip()[:200]
                                                   or f"exit status {result.returncode}"))


def start_daemon(serial, credential_dir, argv, timeout):
    """Run argv through the CLI's mTLS exec (existing credentials only) within a total wall-clock limit."""
    command = [sys.executable, "-I", str(CLI), "--serial", serial, "--mode", "mtls",
               "--credential-dir", str(credential_dir), "--outer", "--", *argv]
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=sys.stderr, stderr=sys.stderr)
    try:
        status = child.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        child.send_signal(signal.SIGINT)  # lets the CLI remove its adb forwards
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        raise RuntimeError(f"SSH start command did not finish within {timeout:g}s.") from None
    if status != 0:
        raise RuntimeError(f"SSH start command exited with status {status}.")


def ensure_listener(device, port, args, sleep=time.sleep, monotonic=time.monotonic):
    if probe_listener(device.serial, port, args.probe_timeout):
        return
    argv = device.alias.ssh_start_argv if device.alias else ()
    if args.no_start or not argv:
        raise RuntimeError(f"No SSH listener on device port {port}, and no start command is configured "
                           "(alias ssh.start_argv) or starting is disabled.")
    if device.credential_error and not args.credential_dir:
        raise RuntimeError(device.credential_error)
    print(f"SSH listener on device port {port} is down; starting it.", file=sys.stderr)
    credential_dir = args.credential_dir or device.credential_dir
    # A failed start is not fatal: a concurrent starter may have won. Never stop or restart; re-probe.
    start_error = None
    try:
        start_daemon(device.serial, credential_dir, argv, args.start_timeout)
    except (OSError, RuntimeError) as error:
        start_error = str(error) or type(error).__name__
        print(f"termuxpp-adb-ssh-proxy: {start_error}; re-checking the listener.", file=sys.stderr)
    deadline = monotonic() + args.ready_timeout
    while True:
        try:
            if probe_listener(device.serial, port, args.probe_timeout):
                return
        except ProbeError:
            pass
        if monotonic() + 1 >= deadline:
            detail = f" (start command: {start_error})" if start_error else ""
            raise RuntimeError(f"SSH listener on device port {port} did not come up in time{detail}.")
        sleep(1)


def main(argv=None):
    os.umask(0o077)
    args = parse_args(argv)
    try:
        device = devices.resolve_device(args.serial, args.devices_config,
                                        credential_root=devices.DEFAULT_CREDENTIAL_DIR)
        port = args.port or (device.alias.ssh_port if device.alias else devices.DEFAULT_SSH_PORT)
        ensure_listener(device, port, args)
    except KeyboardInterrupt:
        return 130
    except (OSError, RuntimeError) as error:
        print(f"termuxpp-adb-ssh-proxy: {error}", file=sys.stderr)
        return 1
    command = ["adb", "-s", device.serial, "shell", "-T", "toybox", "nc", "127.0.0.1", str(port)]
    try:
        os.execvp(command[0], command)
    except OSError as error:
        print(f"termuxpp-adb-ssh-proxy: cannot execute adb: {error}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main())
