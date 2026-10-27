"""Stdio proxy in front of tmux-mcp-rs.

Newer MCP clients (codex, agy) open with a `server/discover` request.
tmux-mcp-rs only accepts `initialize` first and aborts the handshake on
anything else, so answer `server/discover` with "method not found" here and
let the client fall back to `initialize`.
"""

import json
import subprocess
import sys
import threading

METHOD_NOT_FOUND = -32601


def pump_server_output(proc, lock):
    for line in proc.stdout:
        with lock:
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()


def main():
    proc = subprocess.Popen(
        [sys.argv[1], *sys.argv[2:]],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    lock = threading.Lock()
    threading.Thread(
        target=pump_server_output, args=(proc, lock), daemon=True
    ).start()

    for line in sys.stdin.buffer:
        try:
            msg = json.loads(line)
        except ValueError:
            msg = None
        if isinstance(msg, dict) and msg.get("method") == "server/discover":
            if "id" in msg:
                reply = {
                    "jsonrpc": "2.0",
                    "id": msg["id"],
                    "error": {
                        "code": METHOD_NOT_FOUND,
                        "message": "Method not found: server/discover",
                    },
                }
                with lock:
                    sys.stdout.write(json.dumps(reply) + "\n")
                    sys.stdout.flush()
            continue
        proc.stdin.write(line)
        proc.stdin.flush()

    proc.stdin.close()
    sys.exit(proc.wait())


if __name__ == "__main__":
    main()
