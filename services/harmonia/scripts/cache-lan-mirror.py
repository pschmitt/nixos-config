#!/usr/bin/env python3
"""Keep the current main outputs of selected targets in this host's store.

niks3 stores each pin as the object `pins/<name>` (holding its store path) in
the cache bucket; nixbot pins every attribute's latest default-branch output.
Realising them here (through the configured substituters, i.e. the S3 cache
first) and rooting them lets the local Harmonia serve them to LAN clients.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

ROOTS = Path(os.environ.get("NIX_LAN_MIRROR_ROOTS", "/nix/var/nix/gcroots/lan-mirror"))
NIX_STORE = os.environ.get("NIX_STORE_BIN", "nix-store")
# Free space that must remain on the store's filesystem after a fetch.
MIN_FREE = int(os.environ.get("NIX_LAN_MIRROR_MIN_FREE", str(100 * 1024**3)))
UNITS = {"KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")


def s3_client():
    session = boto3.Session(profile_name=os.environ.get("NIX_LAN_MIRROR_S3_PROFILE") or None)
    return session.client(
        "s3",
        endpoint_url=os.environ["NIX_LAN_MIRROR_S3_ENDPOINT"],
        region_name=os.environ.get("NIX_LAN_MIRROR_S3_REGION", "default"),
        config=Config(s3={"addressing_style": "path"}, connect_timeout=30, read_timeout=30),
    )


def pinned_path(s3, bucket, pin):
    """The pin's store path, or None if the pin does not exist."""
    try:
        response = s3.get_object(Bucket=bucket, Key=f"pins/{pin}")
    except ClientError as error:
        if error.response["Error"]["Code"] in ("NoSuchKey", "404"):
            return None
        raise
    path = response["Body"].read().decode().strip()
    if not STORE_PATH.fullmatch(path):
        raise ValueError(f"Unexpected store path in pin {pin}: {path!r}")
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
    bucket, prefix, *targets = sys.argv[1:]
    s3 = s3_client()
    wanted = {}
    failed = []
    for target in targets:
        try:
            path = pinned_path(s3, bucket, prefix + target)
        except (BotoCoreError, ClientError, ValueError) as error:
            print(f"Could not look up {target}: {error}", flush=True)
            failed.append(target)
            continue
        if path is None:
            print("Not pinned:", prefix + target, flush=True)
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
    # that is not pinned (or that failed) keeps its previous output.
    for root in ROOTS.iterdir():
        if not root.name.startswith(".incoming-") and root.name not in targets:
            root.unlink()
            print("Released", root.name)
    if failed:
        raise SystemExit(f"LAN mirror failed for: {', '.join(failed)}")


if __name__ == "__main__":
    main()
