#!/usr/bin/env python3
"""Select build targets from the complete diff; unknown changes build everything."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path, PurePosixPath

# nixbot builds and evaluates every x86_64-linux target; GitHub Actions only
# builds aarch64-linux, natively on arm runners.
GITHUB_SYSTEM = "aarch64-linux"


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def evaluate_drv(attribute, root=".", revision=None):
    """Cache successful derivation paths by exact commit, target and evaluator."""
    cache_dir = os.environ.get("CI_DRV_CACHE")
    revision = revision or os.environ.get("CI_HEAD_SHA")
    cached = None
    if cache_dir and revision:
        schema = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        key = hashlib.sha256(f"{schema}:{revision}:{attribute}".encode()).hexdigest()
        cached = Path(cache_dir) / f"{key}.json"
        try:
            value = json.loads(cached.read_text())
            if (
                value.get("revision") == revision
                and value.get("attribute") == attribute
                and re.fullmatch(
                    r"/nix/store/[a-z0-9]{32}-[^/\n]+\.drv", value.get("drv", "")
                )
            ):
                return value["drv"]
        except (OSError, ValueError, AttributeError, TypeError):
            pass
    args = ["nix", "eval", "--raw"]
    if attribute.startswith("nixOnDroidConfigurations."):
        args.append("--impure")
    drv = output(*args, f"{root}#{attribute}")
    if cached is not None:
        cached.parent.mkdir(parents=True, exist_ok=True)
        # A unique temporary file keeps concurrent host evaluations independent.
        with tempfile.NamedTemporaryFile(
            mode="w", dir=cached.parent, delete=False
        ) as handle:
            json.dump(
                {"revision": revision, "attribute": attribute, "drv": drv}, handle
            )
            temporary = Path(handle.name)
        temporary.replace(cached)
    return drv


def prune_cache(base):
    """Keep only the compared revisions so restored caches do not grow forever."""
    directory = os.environ.get("CI_DRV_CACHE")
    if not directory:
        return
    revisions = {base, os.environ.get("CI_HEAD_SHA")}
    for entry in Path(directory).glob("*.json"):
        try:
            if json.loads(entry.read_text()).get("revision") in revisions:
                continue
        except (OSError, ValueError, AttributeError):
            pass
        entry.unlink(missing_ok=True)


def empty_matrix():
    return {
        "pkgs": {k: [] for k in ("free", "nonfree", "oci")},
        "hosts": {"aarch64": []},
        "droid": False,
    }


def needs_build(path):
    automation = {
        ".github/workflows/nix-systempackages-diff.yaml",
        ".github/workflows/nix-update.yaml",
        ".github/workflows/nix-update-merge.yaml",
        ".github/workflows/flake-lock.yaml",
        ".github/workflows/statix.yml",
        ".github/workflows/scripts/pr-impact.py",
        ".github/workflows/scripts/pr-impact-snapshot.nix",
        ".github/workflows/scripts/pr-packages-diff-comment.sh",
        ".github/workflows/scripts/merge-checked-updates.py",
        ".github/workflows/scripts/auto-merge-nix-update.sh",
        "scripts/nix-update-release-notes.py",
        "scripts/nix-update-release-notes.sh",
    }
    return not (
        path.endswith(".md")
        or path.startswith(("docs/", ".github/tests/"))
        or path in automation
    )


def changed_files(base, event):
    if event == "workflow_dispatch" or not base or set(base) == {"0"}:
        return None
    # Include both sides of renames; a missing base fails instead of guessing.
    return output(
        "git", "diff", "--name-only", "--no-renames", base, "HEAD"
    ).splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--classify-only",
        action="store_true",
        help="Print whether Nix setup is needed, without invoking Nix",
    )
    parser.add_argument(
        "--tooling-only",
        action="store_true",
        help="Print whether CI tooling checks are needed",
    )
    args = parser.parse_args()
    base = os.environ.get("BASE_SHA", "")
    event = os.environ.get("EVENT_NAME", "workflow_dispatch")
    files = changed_files(base, event)
    if args.tooling_only:
        needed = files is None or any(
            p == "flake.lock"
            or p.startswith(
                (
                    ".github/workflows/",
                    ".github/actions/",
                    ".github/tests/",
                    "scripts/nix-update",
                    "services/harmonia",
                    "profiles/specializations/server/scripts/filesystem-available.sh",
                )
            )
            for p in files or []
        )
        print("true" if needed else "false")
        return
    relevant = None if files is None else [f for f in files if needs_build(f)]
    if args.classify_only:
        print("false" if relevant == [] else "true")
        return
    if relevant == []:
        print(json.dumps(empty_matrix(), separators=(",", ":")))
        return

    prune_cache(base)

    # Discover only names for host-only edits. Do not instantiate all package
    # metadata or unrelated host modules just to classify one host's change.
    host_only = relevant and all(
        len(PurePosixPath(p).parts) >= 3 and p.startswith("hosts/") for p in relevant
    )
    if host_only:
        names = json.loads(
            output(
                "nix",
                "eval",
                "--json",
                ".#nixosConfigurations",
                "--apply",
                "builtins.attrNames",
            )
        )
        selected = {PurePosixPath(p).parts[1] for p in relevant}
        if selected <= set(names):
            matrix = empty_matrix()
            for host in sorted(selected):
                system = output(
                    "nix",
                    "eval",
                    "--raw",
                    f".#nixosConfigurations.{host}.config.nixpkgs.system",
                )
                if system == "x86_64-linux":
                    continue
                if system != GITHUB_SYSTEM:
                    raise ValueError(f"Unsupported host architecture: {host}: {system}")
                evaluate_drv(
                    f"nixosConfigurations.{host}.config.system.build.toplevel.drvPath"
                )
                matrix["hosts"]["aarch64"].append(host)
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

    # Evaluate every aarch64 host, including package-only changes: evaluating a
    # package alone does not catch module assertions or host integration
    # failures.
    def evaluate_host(host, root=".", revision=None):
        return evaluate_drv(
            f"nixosConfigurations.{host}.config.system.build.toplevel.drvPath",
            root,
            revision,
        )

    # Bound evaluation too: two workers shorten setup without evaluating every
    # system concurrently and exhausting the runner's memory.
    ordered_hosts = sorted(matrix["hosts"]["aarch64"])
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
                base_drvs = dict(
                    zip(
                        ordered_hosts,
                        workers.map(
                            lambda host: evaluate_host(host, f"path:{baseline}", base),
                            ordered_hosts,
                        ),
                    )
                )
            hosts = {
                host for host in ordered_hosts if host_drvs[host] != base_drvs[host]
            }
            droid_attr = "nixOnDroidConfigurations.zf10.activationPackage.drvPath"
            droid = evaluate_drv(droid_attr) != evaluate_drv(
                droid_attr, f"path:{baseline}", base
            )
        broad = False

    for category in ("free", "nonfree", "oci"):
        matrix["pkgs"][category] = [
            {"pkg": package, "system": system}
            for package in matrix["pkgs"][category]
            if broad or package["name"] in packages
            for system in package["systems"]
            if system == GITHUB_SYSTEM
        ]
    matrix["hosts"] = {
        "aarch64": [host for host in ordered_hosts if broad or host in hosts]
    }
    matrix["droid"] = droid
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
