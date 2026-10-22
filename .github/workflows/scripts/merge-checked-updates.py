#!/usr/bin/env python3
"""Check opt-in package update PRs once; subsequent CI events retry pending PRs."""

import base64
import json
import re
import subprocess


def gh(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def main():
    prs = gh("pr", "list", "--base", "main", "--label", "nix-update-patch",
             "--json", "number,headRefName,isDraft", "--limit", "100")
    for pr in prs:
        prefix = "chore/nix-update/"
        branch = pr["headRefName"]
        if pr["isDraft"] or not branch.startswith(prefix):
            continue
        package = branch.removeprefix(prefix)
        if not package or "/" in package:
            continue
        details = gh("pr", "view", str(pr["number"]), "--json",
                     "files,headRefOid,baseRefOid,isCrossRepository")
        if details["isCrossRepository"]:
            continue
        # A label cannot turn an unrelated PR into a package update.
        paths = [f["path"] for f in details["files"]]
        allowed = [f"pkgs/{package}/", f"pkgs/local/{package}/",
                   f"pkgs/fonts/{package}/"]
        if not paths or not all(any(p.startswith(root) for root in allowed) for p in paths):
            continue
        # Recheck the patch policy and versions at the current head. Labels can
        # survive later updates to the same branch; they are only an opt-in.
        default_file = next((root + "default.nix" for root in allowed
                             if root + "default.nix" in paths), None)
        if default_file is None:
            continue
        repo = subprocess.check_output(
            ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            text=True).strip()
        sources = []
        for ref in (details["baseRefOid"], details["headRefOid"]):
            content = gh("api", f"repos/{repo}/contents/{default_file}?ref={ref}")
            sources.append(base64.b64decode(content["content"]).decode())
        versions = [re.search(r'\bversion\s*=\s*"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"',
                              source) for source in sources]
        if not all(versions):
            continue
        before, after = [tuple(map(int, version.groups())) for version in versions]
        if before[:2] != after[:2] or after[2] <= before[2]:
            continue
        if not all(re.search(r'updatePolicy\.autoMerge\s*=\s*"patch"', source)
                   for source in sources):
            continue
        subprocess.run(["bash", ".github/workflows/scripts/auto-merge-nix-update.sh",
                        str(pr["number"]), package, details["headRefOid"]], check=True)


if __name__ == "__main__":
    main()
