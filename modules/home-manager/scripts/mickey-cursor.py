"""Hide the Hyprland cursor while Mickey sends input to another desktop."""

import json
import os
from pathlib import Path
import socket
import sys
import time

RUNTIME = Path(os.environ["XDG_RUNTIME_DIR"]) / "mickey"
HIDDEN = RUNTIME / "cursor-hidden"


def hyprland(request):
    endpoint = RUNTIME.parent / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(str(endpoint))
        connection.sendall(request.encode())
        with connection.makefile("r", encoding="utf-8") as response:
            return response.read().strip()


def set_invisible(invisible):
    value = "true" if invisible else "false"
    result = hyprland(f"eval hl.config({{ cursor = {{ invisible = {value} }} }})")
    if result != "ok":
        raise RuntimeError(f"Hyprland rejected cursor visibility change: {result}")


def restore():
    if HIDDEN.exists():
        set_invisible(False)
        HIDDEN.unlink(missing_ok=True)


def hide():
    if HIDDEN.exists() or json.loads(hyprland("j/getoption cursor:invisible"))["bool"]:
        return
    # Record ownership before changing the compositor so ExecStopPost can
    # recover even if this process dies immediately after the request.
    HIDDEN.touch()
    set_invisible(True)


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
                    for status in statuses:
                        focus, here, *_ = status.rstrip("\n").split("\t")
                        if focus != "0" and here == "elsewhere":
                            hide()
                        else:
                            restore()
            except ConnectionError:
                pass
            finally:
                restore()
        time.sleep(0.5)


if __name__ == "__main__":
    restore()
    if sys.argv[1:] != ["--restore"]:
        follow()
