#!/usr/bin/env python3
"""Bounded main-branch cache population and replication on a persistent builder."""

import fcntl
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

NIX = os.environ.get("NIX_BIN", "nix")
RETAIN = os.environ["NIX_CACHE_RETAIN"]
REPLICA = os.environ["NIX_CACHE_REPLICA"]
DIRECTORY = Path("/var/lib/nixos-config-cache-populate")
MINIMUM = 15 * 1024**3
SSH = ["ssh", *shlex.split(os.environ.get("NIX_SSHOPTS", ""))]
DEADLINE = time.monotonic() + 10800


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def publish(record, replica=False):
    argv = [RETAIN, "publish"]
    if replica:
        argv = [*SSH, REPLICA, "/run/current-system/sw/bin/nix-cache-retain", "publish"]
    subprocess.run(argv, input=json.dumps(record), text=True, check=True, timeout=120)


def replicate(state):
    failures = []
    records = json.loads(command(RETAIN, "list"))
    for record in records:
        if time.monotonic() >= DEADLINE:
            break
        if record["scope"] != "main":
            continue
        key = record["target"]
        previous = state.get("replicas", {}).get(key, {})
        if (
            isinstance(previous, dict)
            and previous.get("paths") == record["paths"]
            and time.time() - previous.get("verified", 0) < 86400
        ):
            continue
        try:
            store = f"ssh://{REPLICA}"
            # HTTP narinfos are signed by Harmonia on demand. Also persist the
            # primary's signatures for direct SSH copies of third-party paths.
            subprocess.run(
                [
                    NIX,
                    "store",
                    "sign",
                    "--recursive",
                    "--key-file",
                    os.environ["NIX_CACHE_SIGN_KEY"],
                    *record["paths"],
                ],
                check=True,
                timeout=300,
            )
            closure = command(
                NIX, "path-info", "--json", "--recursive", *record["paths"]
            )
            subprocess.run(
                [
                    *SSH,
                    REPLICA,
                    "/run/current-system/sw/bin/nix-cache-retain",
                    "capacity",
                ],
                input=closure,
                text=True,
                check=True,
                timeout=120,
            )
            subprocess.run(
                [
                    NIX,
                    "copy",
                    "--substitute-on-destination",
                    "--to",
                    store,
                    *record["paths"],
                ],
                check=True,
                timeout=1800,
            )
            publish(record, replica=True)
            state.setdefault("replicas", {})[key] = {
                "paths": record["paths"],
                "verified": int(time.time()),
            }
            save(state)
        except (subprocess.SubprocessError, RuntimeError) as error:
            print(f"Replication failed for {key}: {error}", file=sys.stderr, flush=True)
            failures.append(key)
    return failures


def targets(matrix):
    result = []
    for package in matrix["pkgs"]["all"]:
        for system in package["systems"]:
            result.append((f"packages.{system}.{package['name']}", True))
    for names in matrix["hosts"].values():
        for host in names:
            result.append(
                (f"nixosConfigurations.{host}.config.system.build.toplevel", False)
            )
    return sorted(set(result))


def save(state):
    temporary = DIRECTORY / "state.new"
    temporary.write_text(json.dumps(state))
    temporary.replace(DIRECTORY / "state.json")


def populate(state):
    # Resolve main once so every target in this pass uses the same revision.
    metadata = json.loads(
        command(
            NIX,
            "flake",
            "metadata",
            "--refresh",
            "--json",
            "github:pschmitt/nixos-config/main",
        )
    )
    revision = metadata["locked"]["rev"]
    timestamp = metadata["locked"]["lastModified"]
    source = Path(metadata["path"])
    matrix = json.loads(
        command(
            "bash",
            str(source / ".github/workflows/scripts/nix-gh-build-matrix.sh"),
            cwd=source,
        )
    )
    ordered = targets(matrix)
    known = state.get("targets", {})
    # Host systems behind main go first, so a merge reaches the caches (and
    # the S3/LAN mirrors) within a pass or two instead of a full rotation.
    # One attempt per revision: a host that failed waits for the next one.
    stale = [
        t
        for t in ordered
        if t[0].startswith("nixosConfigurations.")
        and known.get(t[0], {}).get("revision") != revision
    ]
    cursor = state.get("cursor", "")
    rotation = [t for t in ordered if t[0] > cursor] + [
        t for t in ordered if t[0] <= cursor
    ]
    rotation = [t for t in rotation if t not in stale]
    started = time.monotonic()
    failures = []
    for target, impure in (stale + rotation)[:8]:
        if time.monotonic() - started > 7200 or time.monotonic() >= DEADLINE:
            break
        try:
            flags = ["--impure"] if impure else []
            ref = f"path:{source}#{target}"
            probe = subprocess.run(
                [NIX, "path-info", *flags, ref],
                text=True,
                capture_output=True,
                timeout=180,
            )
            if probe.returncode == 0:
                paths = probe.stdout.strip().splitlines()
            else:
                usage = os.statvfs("/nix/store")
                if usage.f_bavail * usage.f_frsize < MINIMUM:
                    raise RuntimeError(
                        "Primary has less than 15 GiB available; deferring missing output"
                    )
                paths = command(
                    NIX,
                    "build",
                    "--store",
                    "local",
                    "--builders",
                    "",
                    "--out-link",
                    str(DIRECTORY / "build-result"),
                    "--print-out-paths",
                    "--max-jobs",
                    "1",
                    "--cores",
                    "2",
                    *flags,
                    ref,
                    timeout=3600,
                ).splitlines()
            publish(
                {
                    "target": target,
                    "scope": "main",
                    "revision": revision,
                    "timestamp": timestamp,
                    "paths": paths,
                }
            )
            for result in DIRECTORY.glob("build-result*"):
                if result.is_symlink():
                    result.unlink()
            state.setdefault("targets", {})[target] = {
                "revision": revision,
                "status": "retained",
            }
        except (subprocess.SubprocessError, RuntimeError) as error:
            print(
                f"Population failed for {target}: {error}", file=sys.stderr, flush=True
            )
            failures.append(target)
            state.setdefault("targets", {})[target] = {
                "revision": revision,
                "status": "failed",
            }
        if (target, impure) in rotation:
            state["cursor"] = target
        state["revision"] = revision
        state["total_targets"] = len(ordered)
        state["updated"] = int(time.time())
        save(state)
    return failures


def smoke_test(path):
    # Import the entire canary closure through HTTP into an empty store. Nix
    # verifies signatures during import; never mark this source trusted=true.
    with tempfile.TemporaryDirectory(prefix="nix-cache-smoke-") as directory:
        subprocess.run(
            [
                NIX,
                "copy",
                "--option",
                "require-sigs",
                "true",
                "--from",
                os.environ.get("NIX_CACHE_HTTP_URL", "http://127.0.0.1:42766"),
                "--to",
                directory,
                path,
            ],
            check=True,
            timeout=300,
        )
        subprocess.run(
            [
                NIX,
                "store",
                "verify",
                "--store",
                directory,
                "--recursive",
                "--sigs-needed",
                "1",
                path,
            ],
            check=True,
            timeout=300,
        )


def main():
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    os.environ["NIXPKGS_ALLOW_UNFREE"] = "1"
    with (DIRECTORY / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        file = DIRECTORY / "state.json"
        state = json.loads(file.read_text()) if file.exists() else {}
        failures = replicate(state)
        failures += populate(state)
        failures += replicate(state)
        smoke_test(sys.argv[1])
        save(state)
        if failures:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
