#!/usr/bin/env python3
"""Retain published closures independently of build directories and profiles."""

import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOTS = Path(os.environ.get("NIX_CACHE_ROOTS", "/nix/var/nix/gcroots/nixos-config"))
STATE = Path(os.environ.get("NIX_CACHE_STATE", "/var/lib/nixos-config-cache"))
NIX = os.environ.get("NIX_BIN", "nix")
# S3 mirror (niks3): server URL and token file come from the environment.
NIKS3 = os.environ.get("NIKS3_BIN", "niks3")
S3_STATE = Path(os.environ.get("NIX_CACHE_S3_STATE", "/var/lib/nixos-config-cache-s3"))


def name(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,200}", value):
        raise ValueError("Invalid cache target or scope")
    return value


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
        json.dump(value, handle)
        temporary = Path(handle.name)
    temporary.chmod(0o664)
    temporary.replace(path)


def publish(record):
    scope = name(record["scope"])
    if scope != "main" and not re.fullmatch(r"pr-[0-9]+|manual", scope):
        raise ValueError("Unsupported publication scope")
    target = name(record["target"])
    paths = sorted(set(record["paths"]))
    if not paths or any(
        not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/\n]+", p) for p in paths
    ):
        raise ValueError("Expected realized store output paths")
    timestamp = int(record["timestamp"])
    metadata = STATE / scope / f"{target}.json"
    if metadata.exists() and json.loads(metadata.read_text())["timestamp"] > timestamp:
        print("Ignoring an older publication for", target)
        return
    directory = ROOTS / scope / target
    directory.mkdir(parents=True, exist_ok=True)
    incoming = []
    try:
        for index, path in enumerate(paths):
            root = directory / f"incoming-{index}"
            root.unlink(missing_ok=True)
            root.symlink_to(path)
            incoming.append(root)
        subprocess.run(
            [NIX, "path-info", "--recursive", *paths],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        # Verify signatures through the actual Harmonia endpoint, not SSH.
        subprocess.run(
            [
                NIX,
                "store",
                "verify",
                "--no-contents",
                "--sigs-needed",
                "1",
                "--store",
                "http://127.0.0.1:42766",
                *paths,
            ],
            check=True,
        )
        for index, root in enumerate(incoming):
            root.replace(directory / str(index))
        for root in directory.iterdir():
            if root.name not in {str(i) for i in range(len(paths))}:
                root.unlink()
    finally:
        for root in incoming:
            root.unlink(missing_ok=True)
    atomic_json(metadata, {**record, "paths": paths, "published": int(time.time())})
    print(f"Retained {scope}/{target}: {len(paths)} output(s)")


def prune(days=3):
    cutoff = time.time() - days * 86400
    # Only PR/manual roots expire. Main outputs remain until replaced.
    for directory in STATE.iterdir():
        if not directory.is_dir() or directory.name == "main":
            continue
        if not re.fullmatch(r"pr-[0-9]+|manual", directory.name):
            continue
        for entry in directory.glob("*.json"):
            record = json.loads(entry.read_text())
            if record["published"] >= cutoff:
                continue
            roots = ROOTS / directory.name / entry.stem
            if roots.exists():
                for root in roots.iterdir():
                    root.unlink()
                roots.rmdir()
            entry.unlink()


def pin_names(record):
    return {
        f"main-{record['target']}-{index}": path
        for index, path in enumerate(record["paths"])
    }


def s3_sync(records, everything=False):
    """Push retained main closures to niks3 and pin each target's outputs.

    Only targets whose outputs changed since the last mirror are pushed,
    unless everything is set. Pins of targets no longer retained are removed,
    so niks3's GC can collect them.
    """
    S3_STATE.mkdir(parents=True, exist_ok=True)
    with (S3_STATE / ".lock").open("a") as lock:
        # The path-triggered and nightly runs share this state.
        fcntl.flock(lock, fcntl.LOCK_EX)
        _s3_sync(records, everything)


def _s3_sync(records, everything):
    mirrored_file = S3_STATE / "mirrored.json"
    mirrored = json.loads(mirrored_file.read_text()) if mirrored_file.exists() else {}
    wanted = {}
    failed = []
    for record in sorted(records, key=lambda r: r["target"]):
        pins = pin_names(record)
        wanted.update(pins)
        if not everything and all(mirrored.get(n) == p for n, p in pins.items()):
            continue
        try:
            subprocess.run([NIKS3, "push", *pins.values()], check=True)
            for pin, path in pins.items():
                subprocess.run([NIKS3, "pins", "create", pin, path], check=True)
        except subprocess.CalledProcessError:
            failed.append(record["target"])
            continue
        mirrored.update(pins)
        atomic_json(mirrored_file, mirrored)
        print(f"Mirrored main/{record['target']}: {len(pins)} output(s)", flush=True)
    # Never mistake an empty or unreadable publication state for "delete all".
    if wanted:
        existing = subprocess.check_output(
            [NIKS3, "pins", "list", "--names-only"], text=True
        ).split()
        for pin in existing:
            if pin.startswith("main-") and pin not in wanted:
                subprocess.run([NIKS3, "pins", "delete", pin], check=True)
                print("Removed stale pin", pin)
        mirrored = {n: p for n, p in mirrored.items() if n in wanted}
        atomic_json(mirrored_file, mirrored)
    if failed:
        raise SystemExit(f"S3 mirror failed for: {', '.join(failed)}")


def capacity(closure, reserve=15 * 1024**3):
    if isinstance(closure, list):
        closure = {entry["path"]: entry for entry in closure}
    paths = list(closure)
    if any(not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/\n]+", p) for p in paths):
        raise ValueError("Invalid closure paths")
    invalid = []
    store = str(Path(NIX).with_name("nix-store"))
    for offset in range(0, len(paths), 256):
        invalid.extend(
            subprocess.check_output(
                [
                    store,
                    "--check-validity",
                    "--print-invalid",
                    *paths[offset : offset + 256],
                ],
                text=True,
            ).splitlines()
        )
    needed = sum(int(closure[path]["narSize"]) for path in invalid)
    usage = os.statvfs("/nix/store")
    available = usage.f_bavail * usage.f_frsize
    result = {
        "available": available,
        "missing_bytes": needed,
        "fits": needed == 0 or available - needed >= reserve,
    }
    print(json.dumps(result))
    return result["fits"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=["publish", "prune", "list", "space", "capacity", "s3-sync"]
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="s3-sync: push every retained main target, not only changed ones",
    )
    args = parser.parse_args()
    os.umask(0o002)
    STATE.mkdir(parents=True, exist_ok=True)
    # The remote-builder account intentionally has /var/empty as its home.
    # Give each publisher its own writable Nix narinfo cache instead.
    client_cache = STATE / "clients" / str(os.getuid())
    client_cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.environ["XDG_CACHE_HOME"] = str(client_cache)
    with (STATE / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "s3-sync":
            records = [json.loads(p.read_text()) for p in (STATE / "main").glob("*.json")]
            # Uploads can take hours; do not block publications meanwhile.
            fcntl.flock(lock, fcntl.LOCK_UN)
            s3_sync(records, everything=args.all)
        elif args.action == "publish":
            publish(json.load(sys.stdin))
        elif args.action == "prune":
            prune()
        elif args.action == "capacity":
            if not capacity(json.load(sys.stdin)):
                raise SystemExit("Insufficient room for closure and 15 GiB reserve")
        elif args.action == "space":
            usage = os.statvfs("/nix/store")
            print(usage.f_bavail * usage.f_frsize)
        else:
            records = [json.loads(p.read_text()) for p in STATE.glob("*/*.json")]
            print(json.dumps(records))


if __name__ == "__main__":
    main()
