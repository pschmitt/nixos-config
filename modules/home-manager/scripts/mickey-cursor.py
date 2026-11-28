"""Publish the parked pointer location while Mickey input is elsewhere."""

import json
import os
from pathlib import Path
import socket
import sys
import time

RUNTIME = Path(os.environ["XDG_RUNTIME_DIR"]) / "mickey"
HIDDEN = RUNTIME / "cursor-hidden"
INDICATOR = RUNTIME.parent / "mickey-away.json"


def hyprland(request):
    endpoint = RUNTIME.parent / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(str(endpoint))
        connection.sendall(request.encode())
        with connection.makefile("r", encoding="utf-8") as response:
            return response.read().strip()


def publish(position):
    temporary = INDICATOR.with_name(f".{INDICATOR.name}.{os.getpid()}")
    temporary.write_text(json.dumps(position))
    temporary.replace(INDICATOR)


def clear():
    if INDICATOR.exists() and INDICATOR.read_text() != "null":
        publish(None)


def restore():
    clear()
    # Clear a hide left by the previous version if it exited uncleanly.
    if HIDDEN.exists():
        result = hyprland("eval hl.config({ cursor = { invisible = false } })")
        if result == "ok":
            HIDDEN.unlink(missing_ok=True)


def show_away():
    x, y = map(int, hyprland("cursorpos").split(","))
    publish({"x": x, "y": y})


def follow():
    while True:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            try:
                connection.connect(str(RUNTIME / "control.sock"))
                connection.sendall(b"follow\n")
            except (FileNotFoundError, ConnectionError):
                time.sleep(0.5)
                continue

            try:
                with connection.makefile("r", encoding="utf-8") as statuses:
                    away = False
                    for status in statuses:
                        _, here, *_ = status.rstrip("\n").split("\t")
                        now_away = here == "elsewhere"
                        if now_away != away:
                            (show_away if now_away else clear)()
                            away = now_away
            except ConnectionError:
                pass
            finally:
                clear()
        time.sleep(0.5)


if __name__ == "__main__":
    restore()
    if sys.argv[1:] != ["--restore"]:
        follow()
