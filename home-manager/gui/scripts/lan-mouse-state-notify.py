"""Follow local daemon routing events; notifications never determine state."""

import json
import os
import socket
import subprocess
import sys


def notify(helper, *args):
    try:
        subprocess.run([helper, *args], check=False, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        pass


def main():
    helper = sys.argv[1]
    peer = None
    notify(helper, "dismiss")
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], "lan-mouse-socket.sock"))
            connection.sendall(b'"InputState"\n')
            with connection.makefile("r") as events:
                for line in events:
                    snapshot = json.loads(line).get("InputState")
                    if snapshot is None:
                        continue
                    outgoing = snapshot.get("outgoing")
                    if outgoing != peer:
                        if outgoing:
                            notify(helper, "show", outgoing)
                        else:
                            notify(helper, "dismiss")
                        peer = outgoing
    finally:
        notify(helper, "dismiss")


if __name__ == "__main__":
    main()
