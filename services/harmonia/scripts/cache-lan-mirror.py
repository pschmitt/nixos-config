#!/usr/bin/env python3
"""Keep the current main outputs of selected targets in this host's store.

The cache host's `nix-cache-retain list` names the retained main outputs.
Realising them here (through the configured substituters, i.e. the S3 cache
first) and rooting them lets the local Harmonia serve them to LAN clients.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOTS = Path(os.environ.get("NIX_LAN_MIRROR_ROOTS", "/nix/var/nix/gcroots/lan-mirror"))
NIX_STORE = os.environ.get("NIX_STORE_BIN", "nix-store")


def main():
    source, *targets = sys.argv[1:]
    ssh = os.environ.get("NIX_LAN_MIRROR_SSH", "ssh").split()
    records = json.loads(
        subprocess.check_output([*ssh, source, "nix-cache-retain", "list"], text=True)
    )
    wanted = {}
    for record in records:
        if record["scope"] == "main" and record["target"] in targets:
            for index, path in enumerate(record["paths"]):
                wanted[f"{record['target']}-{index}"] = path
    missing = sorted(
        set(targets) - {r["target"] for r in records if r["scope"] == "main"}
    )
    if missing:
        print("Not retained on the cache host:", ", ".join(missing))

    ROOTS.mkdir(parents=True, exist_ok=True)
    failed = []
    for name, path in sorted(wanted.items()):
        root = ROOTS / name
        if root.is_symlink() and os.readlink(root) == path:
            continue
        incoming = ROOTS / f".incoming-{name}"
        incoming.unlink(missing_ok=True)
        try:
            subprocess.run(
                [NIX_STORE, "--realise", path, "--add-root", str(incoming)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            incoming.unlink(missing_ok=True)
            failed.append(name)
            continue
        incoming.replace(root)
        print(f"Mirrored {name}: {path}", flush=True)

    # Release outputs that were replaced or whose targets were dropped, but
    # never mistake an empty answer from the cache host for "release all".
    for root in ROOTS.iterdir() if wanted else []:
        if root.name not in wanted:
            root.unlink()
            print("Released", root.name)
    if failed:
        raise SystemExit(f"LAN mirror failed for: {', '.join(failed)}")


if __name__ == "__main__":
    main()
