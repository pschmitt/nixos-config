#!/usr/bin/env python3
"""Select build targets from the complete diff; unknown changes build everything."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import PurePosixPath
import subprocess
import tempfile


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

    def needs_build(path):
        reporting_files = {
            ".github/workflows/nix-systempackages-diff.yaml",
            ".github/workflows/nix-update.yaml",
            ".github/workflows/scripts/pr-impact.py",
            ".github/workflows/scripts/pr-impact-snapshot.nix",
            ".github/workflows/scripts/pr-packages-diff-comment.sh",
            "scripts/nix-update-release-notes.py",
            "scripts/nix-update-release-notes.sh",
        }
        return not (path.endswith(".md") or path.startswith("docs/") or path in reporting_files)

    relevant = None if files is None else [f for f in files if needs_build(f)]
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
    def evaluate_host(host, root="."):
        return output("nix", "eval", "--raw",
                      f"{root}#nixosConfigurations.{host}.config.system.build.toplevel.drvPath")

    # Bound evaluation too: two workers shorten setup without evaluating every
    # system concurrently and exhausting the runner's memory.
    ordered_hosts = sorted(host_names)
    with ThreadPoolExecutor(max_workers=2) as workers:
        host_drvs = dict(zip(ordered_hosts, workers.map(evaluate_host, ordered_hosts)))

    # Service-only updates (including container tag bumps) do not warrant the
    # package matrix. Compare evaluated systems to cover shared service imports
    # without maintaining an inaccurate service-to-host map.
    service_only = relevant and all(p.startswith("services/") for p in relevant)
    droid = broad
    if service_only and base:
        with tempfile.TemporaryDirectory(prefix="ci-base-") as baseline:
            archive = subprocess.check_output(["git", "archive", base])
            subprocess.run(["tar", "-x", "-C", baseline], input=archive, check=True)
            with ThreadPoolExecutor(max_workers=2) as workers:
                base_drvs = dict(zip(ordered_hosts, workers.map(
                    lambda host: evaluate_host(host, f"path:{baseline}"), ordered_hosts)))
            hosts = {host for host in host_names if host_drvs[host] != base_drvs[host]}
            droid_attr = "nixOnDroidConfigurations.zf10.activationPackage.drvPath"
            droid = output("nix", "eval", "--impure", "--raw", f".#{droid_attr}") != output(
                "nix", "eval", "--impure", "--raw", f"path:{baseline}#{droid_attr}")
        broad = False

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
    matrix["droid"] = droid
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
