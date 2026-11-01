"""Follow local daemon routing events; notifications never determine state."""

import json
import os
import select
import socket
import subprocess
import sys
import time


def notify(helper, *args):
    try:
        subprocess.run([helper, *args], check=False, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        pass


def main():
    helper = sys.argv[1]
    peer = None
    connected = {}
    notify_send = sys.argv[2]
    notify_switch = sys.argv[3] == "true"
    notify(helper, "dismiss")
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], "lan-mouse-socket.sock"))
            buffer = b""
            next_poll = 0.0
            while True:
                now = time.monotonic()
                if now >= next_poll:
                    connection.sendall(b'"InputState"\n')
                    next_poll = now + 1.0
                ready, _, _ = select.select([connection], [], [], max(0, next_poll - now))
                if not ready:
                    continue
                chunk = connection.recv(65536)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    snapshot = json.loads(line).get("InputState")
                    if snapshot is None:
                        continue
                    current = {
                        item["id"]: item["hostname"]
                        for item in snapshot.get("peers", [])
                        if item.get("connected")
                    }
                    for peer_id in current.keys() - connected.keys():
                        notify(notify_send, "--app-name=lan-mouse", "--icon=input-mouse",
                               "Peer connected", current[peer_id])
                    for peer_id in connected.keys() - current.keys():
                        notify(notify_send, "--app-name=lan-mouse", "--icon=input-mouse",
                               "Peer disconnected", connected[peer_id])
                    connected = current
                    if not notify_switch:
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
