#!/usr/bin/env python3
"""Keep the current main outputs of selected targets in this host's store.

nixbot publishes each attribute's latest default-branch output under
`<source URL>/<attribute>` (its `outputsPath`). Realising them here (through
the configured substituters, i.e. the S3 cache first) and rooting them lets
the local Harmonia serve them to LAN clients.
"""

import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOTS = Path(os.environ.get("NIX_LAN_MIRROR_ROOTS", "/nix/var/nix/gcroots/lan-mirror"))
NIX_STORE = os.environ.get("NIX_STORE_BIN", "nix-store")
# Free space that must remain on the store's filesystem after a fetch.
MIN_FREE = int(os.environ.get("NIX_LAN_MIRROR_MIN_FREE", str(100 * 1024**3)))
UNITS = {"KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")


def output_path(source, target):
    """The target's current output, or None if nixbot has not published one."""
    try:
        with urllib.request.urlopen(f"{source}/{target}", timeout=30) as response:
            path = response.read().decode().strip()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    if not STORE_PATH.fullmatch(path):
        raise ValueError(f"Unexpected output for {target}: {path!r}")
    return path


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
    source = source.rstrip("/")
    wanted = {}
    failed = []
    for target in targets:
        try:
            path = output_path(source, target)
        except (OSError, ValueError) as error:
            print(f"Could not look up {target}: {error}", flush=True)
            failed.append(target)
            continue
        if path is None:
            print("Not published by nixbot:", target, flush=True)
            continue
        wanted[target] = path

    ROOTS.mkdir(parents=True, exist_ok=True)
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

    # Release outputs of targets that are no longer configured; a target
    # nixbot has not published (or that failed) keeps its previous output.
    for root in ROOTS.iterdir():
        if not root.name.startswith(".incoming-") and root.name not in targets:
            root.unlink()
            print("Released", root.name)
    if failed:
        raise SystemExit(f"LAN mirror failed for: {', '.join(failed)}")


if __name__ == "__main__":
    main()
