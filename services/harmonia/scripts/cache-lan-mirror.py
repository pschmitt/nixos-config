#!/usr/bin/env python3
"""Keep successful Circus outputs from main rooted for Harmonia LAN clients."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import urlopen

ROOTS = Path(os.environ.get("NIX_LAN_MIRROR_ROOTS", "/nix/var/nix/gcroots/lan-mirror"))
NIX_STORE = os.environ.get("NIX_STORE_BIN", "nix-store")
# Free space that must remain on the store's filesystem after a fetch.
MIN_FREE = int(os.environ.get("NIX_LAN_MIRROR_MIN_FREE", str(100 * 1024**3)))
UNITS = {"KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")


def main_commit(repository):
    output = subprocess.run(
        ["git", "ls-remote", "--exit-code", repository, "refs/heads/main"],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    ).stdout
    commit = output.split("\t", 1)[0]
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Unexpected main commit from git ls-remote")
    return commit


def build_path(jobset, target, commit):
    """The successful job output for this main commit, if available."""
    url = f"{jobset.rstrip('/')}/{quote(target, safe='')}/latest?{urlencode({'commit': commit})}"
    try:
        with urlopen(url, timeout=30) as response:
            path = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            return None
        raise
    if not isinstance(path, str) or not STORE_PATH.fullmatch(path):
        raise ValueError(f"Unexpected store path for {target}")
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
    jobset, repository, *targets = sys.argv[1:]
    commit = main_commit(repository)
    wanted = {}
    failed = []
    for target in targets:
        try:
            path = build_path(jobset, target, commit)
        except (URLError, TimeoutError, ValueError) as error:
            print(f"Could not look up {target}: {error}", flush=True)
            failed.append(target)
            continue
        if path is None:
            print(f"No successful Circus build for {target} at {commit[:12]}", flush=True)
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
    # without a successful build (or that failed) keeps its previous output.
    for root in ROOTS.iterdir():
        if not root.name.startswith(".incoming-") and root.name not in targets:
            root.unlink()
            print("Released", root.name)
    if failed:
        raise SystemExit(f"LAN mirror failed for: {', '.join(failed)}")


if __name__ == "__main__":
    main()
