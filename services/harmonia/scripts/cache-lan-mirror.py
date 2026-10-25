#!/usr/bin/env python3
"""Keep the current main outputs of selected targets in this host's store.

The cache host's `nix-cache-retain list` names the retained main outputs.
Realising them here (through the configured substituters, i.e. the S3 cache
first) and rooting them lets the local Harmonia serve them to LAN clients.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOTS = Path(os.environ.get("NIX_LAN_MIRROR_ROOTS", "/nix/var/nix/gcroots/lan-mirror"))
NIX_STORE = os.environ.get("NIX_STORE_BIN", "nix-store")
# Free space that must remain on the store's filesystem after a fetch.
MIN_FREE = int(os.environ.get("NIX_LAN_MIRROR_MIN_FREE", str(100 * 1024**3)))
UNITS = {"KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}


def fetch_size(path):
    """Unpacked bytes `nix-store --realise path` would add to the store."""
    output = subprocess.run(
        [NIX_STORE, "--realise", "--dry-run", path],
        check=True,
        capture_output=True,
        text=True,
    ).stderr
    match = re.search(r"([0-9.]+) (KiB|MiB|GiB|TiB) unpacked", output)
    return int(float(match[1]) * UNITS[match[2]]) if match else 0


def available():
    usage = os.statvfs("/nix/store")
    return usage.f_bavail * usage.f_frsize


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
            # Keep the previous output (still served) rather than risk the
            # filesystem, which on a typical host is shared with / and VMs.
            needed = fetch_size(path)
            if available() - needed < MIN_FREE:
                print(
                    f"Skipping {name}: needs {needed / 1024**3:.1f} GiB, "
                    f"{available() / 1024**3:.1f} GiB free, "
                    f"keeping {MIN_FREE / 1024**3:.0f} GiB",
                    flush=True,
                )
                failed.append(name)
                continue
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
