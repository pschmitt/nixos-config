#!/usr/bin/env python3
"""Check opt-in package update PRs once; subsequent CI events retry pending PRs."""

import base64
import json
import re
import subprocess


def gh(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def ordered_version(version):
    numeric = re.fullmatch(r"\d+(?:\.\d+){0,2}", version)
    date = re.fullmatch(r"(?:0-)?unstable-(\d{4})-(\d{2})-(\d{2})", version)
    if numeric:
        parts = tuple(map(int, numeric.group().split(".")))
        return "numeric", parts + (0,) * (3 - len(parts))
    if date:
        return "date", tuple(map(int, date.groups()))
    return None


def main():
    prs = gh(
        "pr",
        "list",
        "--base",
        "main",
        "--label",
        "nix-update-patch",
        "--json",
        "number,headRefName,isDraft",
        "--limit",
        "100",
    )
    for pr in prs:
        prefix = "chore/nix-update/"
        branch = pr["headRefName"]
        if pr["isDraft"] or not branch.startswith(prefix):
            continue
        package = branch.removeprefix(prefix)
        if not package or "/" in package:
            continue
        details = gh(
            "pr",
            "view",
            str(pr["number"]),
            "--json",
            "files,headRefOid,baseRefOid,isCrossRepository",
        )
        if details["isCrossRepository"]:
            continue
        # A label cannot turn an unrelated PR into a package update.
        paths = [f["path"] for f in details["files"]]
        allowed = [
            f"pkgs/{package}/",
            f"pkgs/local/{package}/",
            f"pkgs/fonts/{package}/",
            f"pkgs/oci/{package}/",
            f"pkgs/termux/{package}/",
        ]
        package_files = {
            "tesmart-cli": "pkgs/zsh-tools/tesmart-cli.nix",
            "kubectl-ksh": "pkgs/zsh-tools/kubectl-ksh.nix",
            "kubectl-socks5-proxy": "pkgs/zsh-tools/kubectl-socks5-proxy.nix",
            "kubectl-watch": "pkgs/zsh-tools/kubectl-watch.nix",
            "netbird-cli": "pkgs/zsh-tools/netbird-cli.nix",
        }
        default_files = [root + "default.nix" for root in allowed]
        if package in package_files:
            default_files.append(package_files[package])
        if not paths or not all(
            any(p.startswith(root) for root in allowed)
            or p == package_files.get(package)
            for p in paths
        ):
            continue
        # Recheck the opt-in policy and versions at the current head. Labels can
        # survive later updates to the same branch; they are only an opt-in.
        default_file = next((path for path in default_files if path in paths), None)
        if default_file is None:
            continue
        repo = subprocess.check_output(
            ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            text=True,
        ).strip()
        sources = []
        for ref in (details["baseRefOid"], details["headRefOid"]):
            content = gh("api", f"repos/{repo}/contents/{default_file}?ref={ref}")
            sources.append(base64.b64decode(content["content"]).decode())
        version_values = [
            re.findall(r'\bversion\s*=\s*"([^"]+)"', source) for source in sources
        ]
        if not all(version_values) or len(version_values[0]) != len(version_values[1]):
            continue
        changed_versions = [
            (before, after) for before, after in zip(*version_values) if before != after
        ]
        if len(changed_versions) != 1:
            continue
        before, after = changed_versions[0]
        self_maintained = all(
            re.search(r"\bmaintainers\s*=.*?\bpschmitt\b", source, re.DOTALL)
            for source in sources
        )
        policies = [
            re.search(r'updatePolicy\.autoMerge\s*=\s*"(patch|all)"', source)
            for source in sources
        ]
        if self_maintained:
            policy = "all"
        elif all(policies) and policies[0].group(1) == policies[1].group(1):
            policy = policies[0].group(1)
        else:
            continue
        if policy == "patch":
            old = re.fullmatch(
                r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", before
            )
            new = re.fullmatch(
                r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", after
            )
            if not old or not new:
                continue
            old_version = tuple(map(int, old.groups()))
            new_version = tuple(map(int, new.groups()))
            if old_version[:2] != new_version[:2] or new_version[2] <= old_version[2]:
                continue
        else:
            old_version = ordered_version(before)
            new_version = ordered_version(after)
            if (
                old_version is None
                or new_version is None
                or old_version[0] != new_version[0]
                or new_version[1] <= old_version[1]
            ):
                continue
        subprocess.run(
            [
                "bash",
                ".github/workflows/scripts/auto-merge-nix-update.sh",
                str(pr["number"]),
                package,
                details["headRefOid"],
            ],
            check=True,
        )


if __name__ == "__main__":
    main()
