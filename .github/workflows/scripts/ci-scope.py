#!/usr/bin/env python3
"""Select build targets from the complete diff; unknown changes build everything."""

import json
import os
from pathlib import PurePosixPath
import subprocess


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    base = os.environ.get("BASE_SHA", "")
    event = os.environ.get("EVENT_NAME", "workflow_dispatch")
    files = None
    if event != "workflow_dispatch" and base and set(base) != {"0"}:
        # Include both sides of renames, and fail rather than guess if the base
        # is unavailable. Checkout fetches history for push and PR comparisons.
        files = output("git", "diff", "--name-only", "--no-renames", base, "HEAD").splitlines()

    def documentation(path):
        return path.endswith(".md") or path.startswith("docs/")

    relevant = None if files is None else [f for f in files if not documentation(f)]
    if relevant == []:
        matrix = {"pkgs": {k: [] for k in ("free", "nonfree", "oci")},
                  "hosts": {"amd64": [], "aarch64": []}, "droid": False}
        print(json.dumps(matrix, separators=(",", ":")))
        return

    matrix = json.loads(output("./.github/workflows/scripts/nix-gh-build-matrix.sh"))
    package_names = {p["name"] for p in matrix["pkgs"]["all"]}
    host_names = set(matrix["hosts"]["amd64"] + matrix["hosts"]["aarch64"])
    packages, hosts = set(), set()
    broad = relevant is None
    for path in relevant or []:
        parts = PurePosixPath(path).parts
        if len(parts) >= 3 and parts[0] == "hosts" and parts[1] in host_names:
            hosts.add(parts[1])
        elif len(parts) >= 3 and parts[0] == "pkgs":
            # Some package families live one level deeper. Shared definitions,
            # aliases and unknown directories deliberately take the broad path.
            name = parts[1]
            if name in ("local", "oci", "fonts") and len(parts) >= 4:
                name = parts[2]
            if name in package_names:
                packages.add(name)
            else:
                broad = True
        else:
            broad = True

    # Evaluate every host, including package-only changes: evaluating a package
    # alone does not catch module assertions or host integration failures.
    for host in sorted(host_names):
        output("nix", "eval", "--raw",
               f".#nixosConfigurations.{host}.config.system.build.toplevel.drvPath")

    for category in ("free", "nonfree", "oci"):
        matrix["pkgs"][category] = [
            {"pkg": package, "system": system}
            for package in matrix["pkgs"][category]
            if broad or package["name"] in packages
            for system in package["systems"]
        ]
    if not broad:
        for architecture in matrix["hosts"]:
            matrix["hosts"][architecture] = [
                host for host in matrix["hosts"][architecture] if host in hosts
            ]
    matrix["droid"] = broad
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
