#!/usr/bin/env python3
"""Check opt-in package update PRs once; subsequent CI events retry pending PRs."""

import base64
import json
import re
import subprocess


def gh(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


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
        ]
        package_files = {
            "tesmart-cli": "pkgs/zsh-tools/tesmart-cli.nix",
            "kubectl-ksh": "pkgs/zsh-tools/kubectl-ksh.nix",
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
        if not all(version_values):
            continue
        policies = [
            re.search(r'updatePolicy\.autoMerge\s*=\s*"(patch|all)"', source)
            for source in sources
        ]
        if not all(policies) or policies[0].group(1) != policies[1].group(1):
            continue
        policy = policies[0].group(1)
        before, after = [versions[-1] for versions in version_values]
        if policy == "patch":
            old = re.fullmatch(
                r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', before
            )
            new = re.fullmatch(
                r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', after
            )
            if not old or not new:
                continue
            old_version = tuple(map(int, old.groups()))
            new_version = tuple(map(int, new.groups()))
            if old_version[:2] != new_version[:2] or new_version[2] <= old_version[2]:
                continue
        else:
            old_semver = re.fullmatch(
                r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', before
            )
            new_semver = re.fullmatch(
                r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', after
            )
            old_date = re.fullmatch(r'0-unstable-(\d{4})-(\d{2})-(\d{2})', before)
            new_date = re.fullmatch(r'0-unstable-(\d{4})-(\d{2})-(\d{2})', after)
            if old_semver and new_semver:
                if tuple(map(int, new_semver.groups())) <= tuple(
                    map(int, old_semver.groups())
                ):
                    continue
            elif old_date and new_date:
                if tuple(map(int, new_date.groups())) <= tuple(
                    map(int, old_date.groups())
                ):
                    continue
            else:
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
