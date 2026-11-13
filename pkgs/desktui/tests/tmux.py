"""Exercise desktui through a real tmux server and an emulated Kitty terminal."""

import base64
import fcntl
import os
import pty
import re
import select
import shlex
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import zlib
from pathlib import Path


def run_case(binary, root, mode):
    socket = str(root / (mode + ".sock"))
    config = root / "tmux.conf"
    config.write_text(
        "set -g allow-passthrough on\nset -g status off\nset -g remain-on-exit on\n"
        + "set -g default-shell "
        + shlex.quote(os.environ.get("SHELL", "/bin/sh"))
        + "\n"
    )
    command = ["tmux", "-S", socket, "-f", str(config)]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ.pop("TMUX", None)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 1000, 800))
        os.execvp(
            "tmux",
            command
            + [
                "new-session",
                "-s",
                "test",
                shlex.join([binary, mode, "--transfer", "direct", "--fps", "2"]),
            ],
        )

    output = bytearray()
    pending = bytearray()
    replies = 0
    start = time.monotonic()
    try:
        while time.monotonic() - start < 5:
            if not select.select([fd], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            output.extend(chunk)
            pending.extend(chunk)
            # tmux removes the DCS envelope before sending APCs to its client.
            pattern = (
                rb"\x1b_G([^\x1b]*)\x1b\\|\x1b\[(?:0)?c|\x1b\[14t|\x1b\[16t|\x1b\[6n"
            )
            consumed = 0
            for match in re.finditer(pattern, pending):
                consumed = match.end()
                sequence = match.group()
                if sequence.startswith(b"\x1b_G"):
                    header = match.group(1).split(b";", 1)[0]
                    fields = dict(
                        part.split(b"=", 1)
                        for part in header.split(b",")
                        if b"=" in part
                    )
                    if fields.get(b"a") == b"q":
                        image_id = fields[b"i"]
                        os.write(fd, b"\x1b_Gi=" + image_id + b";OK\x1b\\")
                        replies += 1
                elif sequence.endswith(b"c"):
                    os.write(fd, b"\x1b[?62;22c")
                elif sequence == b"\x1b[14t":
                    os.write(fd, b"\x1b[4;800;1000t")
                elif sequence == b"\x1b[16t":
                    os.write(fd, b"\x1b[6;20;10t")
                elif sequence == b"\x1b[6n":
                    os.write(fd, b"\x1b[1;1R")
            if consumed:
                del pending[:consumed]

        try:
            pane = subprocess.check_output(
                command + ["capture-pane", "-p", "-t", "test"], text=True
            )
        except subprocess.CalledProcessError:
            print("Emulated terminal output:", repr(bytes(output[-3000:])), flush=True)
            raise
        if mode == "--print-caps":
            assert re.search(r"kitty graphics\s+yes", pane), pane
            assert replies > 0, "No graphics query reached the outer terminal"
        else:
            tiles = validate_tiles(output)
            assert tiles > 0, "No valid pixel tiles reached the outer terminal"
            assert re.search(
                rb"\x1b7\x1b\[\d+;\d+H\x1b_Ga=T", bytes(output)
            ), "Placements did not carry their own cursor address through tmux"
            # The prefix exits locally; this case never connects to a VNC server.
            subprocess.run(
                command + ["send-keys", "-t", "test", "C-a", "q"], check=True
            )
            for _ in range(30):
                dead = subprocess.check_output(
                    command + ["display-message", "-p", "-t", "test", "#{pane_dead}"],
                    text=True,
                ).strip()
                if dead == "1":
                    break
                time.sleep(0.1)
            assert dead == "1", "desktui did not exit with its local prefix"
            status = subprocess.check_output(
                command
                + ["display-message", "-p", "-t", "test", "#{pane_dead_status}"],
                text=True,
            ).strip()
            assert status == "0", f"desktui exit status: {status}"
            print(f"tmux test pattern: {tiles} validated RGB tiles", flush=True)
        print(f"{mode}: passed", flush=True)
    finally:
        subprocess.run(
            command + ["kill-server"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.close(fd)
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)


def validate_tiles(output):
    sequences = re.findall(rb"\x1b_G([^;\x1b]*);([^\x1b]*)\x1b\\", output)
    params = None
    payload = bytearray()
    tiles = 0
    for header, chunk in sequences:
        fields = dict(
            part.split(b"=", 1) for part in header.split(b",") if b"=" in part
        )
        if b"s" in fields and fields.get(b"a") != b"q":
            params = fields
            payload = bytearray()
        if params is not None:
            payload.extend(chunk)
            if fields.get(b"m") != b"1":
                pixels = base64.b64decode(payload)
                if params.get(b"o") == b"z":
                    pixels = zlib.decompress(pixels)
                expected = (
                    int(params[b"s"])
                    * int(params[b"v"])
                    * (int(params.get(b"f", b"24")) // 8)
                )
                assert len(pixels) == expected
                tiles += 1
                params = None
    return tiles


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(
        prefix="desktui-tmux-", dir=os.environ.get("TMPDIR")
    ) as directory:
        root = Path(directory)
        run_case(sys.argv[1], root, "--print-caps")
        run_case(sys.argv[1], root, "--test-pattern")
