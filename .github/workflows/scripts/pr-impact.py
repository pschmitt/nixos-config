#!/usr/bin/env python3
"""Compare package, kernel and container metadata without building closures."""

import argparse
import hashlib
import html
import json
import os
import subprocess
import sys
import tempfile
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MARKER = "<!-- pr-systempackages-diff -->"
SNAPSHOT = Path(__file__).with_name("pr-impact-snapshot.nix")
DISCOVER = """f: {
  nixos = builtins.attrNames (f.nixosConfigurations or {});
  droid = builtins.filter (n: !(builtins.elem n [ "default" "phone" ]))
    (builtins.attrNames (f.nixOnDroidConfigurations or {}));
}"""


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def nix_json(*args):
    return json.loads(command("nix", "eval", "--impure", "--json", *args))


def export_revision(revision, destination):
    archive = subprocess.check_output(["git", "archive", revision])
    subprocess.run(["tar", "-x", "-C", str(destination)], input=archive, check=True)


def discover(root):
    flake = f"builtins.getFlake {json.dumps('path:' + str(root))}"
    configs = nix_json("--expr", flake, "--apply", DISCOVER)
    return {
        **{f"nixos:{h}": h for h in configs["nixos"]},
        **{f"droid:{h}": h for h in configs["droid"]},
    }


def select_targets(targets, files, requested, include_iso):
    if requested:
        missing = set(requested) - set(targets.values()) - set(targets)
        if missing:
            raise ValueError("Unknown target(s): " + ", ".join(sorted(missing)))
        return sorted(
            k for k, host in targets.items() if k in requested or host in requested
        )
    relevant = [p for p in files if not (p.endswith(".md") or p.startswith("docs/"))]
    directories = set()
    shared = False
    for path in relevant:
        parts = Path(path).parts
        if len(parts) >= 3 and parts[0] == "hosts":
            directories.add(parts[1])
            if parts[1] not in targets.values() and not parts[1].startswith("iso"):
                shared = True
        else:
            shared = True
    # Shared changes take precedence over host-local changes in a mixed PR.
    if shared:
        return sorted(
            k for k, h in targets.items() if include_iso or not h.startswith("iso")
        )
    return sorted(
        k
        for k, h in targets.items()
        if h in directories
        or (h.startswith("iso") and any(d.startswith("iso") for d in directories))
    )


def snapshot(root, revision, target, cache):
    digest = hashlib.sha256(SNAPSHOT.read_bytes()).hexdigest()[:16]
    key = hashlib.sha256(f"{digest}:{revision}:{target}".encode()).hexdigest()
    cached = cache / f"{key}.json"
    if cached.exists():
        try:
            value = json.loads(cached.read_text())
            if isinstance(value, dict) and all(
                k in value for k in ("packages", "kernel", "containers")
            ):
                return value
        except (ValueError, OSError):
            pass
    kind, host = target.split(":", 1)
    attr = "nixosConfigurations" if kind == "nixos" else "nixOnDroidConfigurations"
    # Nix attribute names can contain dashes and other punctuation.
    selector = f"path:{root}#{attr}.{json.dumps(host)}"
    public_source = f"(builtins.getFlake {json.dumps('path:' + str(root))}).outPath"
    expression = f"({SNAPSHOT.read_text()}) {public_source}"
    value = nix_json(selector, "--apply", expression)
    cache.mkdir(parents=True, exist_ok=True)
    temporary = cached.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True))
    temporary.replace(cached)
    return value


def changes(before, after):
    lines = []
    before = before or {"packages": [], "kernel": None, "containers": {}}
    after = after or {"packages": [], "kernel": None, "containers": {}}
    if before["kernel"] != after["kernel"]:

        def kernel(value):
            if value is None:
                return "none"
            version = value["version"]
            modules = value["modDirVersion"]
            return version if version == modules else f"{version} (modules {modules})"

        lines.append(f"Kernel: {kernel(before['kernel'])} → {kernel(after['kernel'])}")
    for name in sorted(before["containers"].keys() | after["containers"].keys()):
        old, new = before["containers"].get(name), after["containers"].get(name)
        if old != new:
            lines.append(f"Container {name}: {old or 'none'} → {new or 'none'}")
    old_packages, new_packages = defaultdict(set), defaultdict(set)
    for p in before["packages"]:
        old_packages[(p["scope"], p["name"])].add(p["version"])
    for p in after["packages"]:
        new_packages[(p["scope"], p["name"])].add(p["version"])
    for scope, name in sorted(old_packages.keys() | new_packages.keys()):
        old = old_packages[(scope, name)]
        new = new_packages[(scope, name)]
        if old == new:
            continue
        label = name if scope == "system" else f"{name} [{scope}]"

        def text(versions):
            return ", ".join(sorted(v or "(unversioned)" for v in versions))

        if not old:
            lines.append(f"+ {label} {text(new)}")
        elif not new:
            lines.append(f"- {label} {text(old)}")
        else:
            lines.append(f"~ {label}: {text(old)} → {text(new)}")
    return tuple(lines)


def render(
    base, head, targets, results, failures, max_lines, run_url, limit_comment=True
):
    groups = defaultdict(list)
    unchanged = []
    for target in targets:
        if target in failures:
            continue
        old, new = results[target]
        delta = changes(old, new)
        if old is None:
            delta = ("Configuration added",) + delta
        elif new is None:
            delta = ("Configuration removed",) + delta
        if delta:
            groups[delta].append(target)
        else:
            unchanged.append(target)
    lines = [
        MARKER,
        "## Configuration impact",
        "",
        f"Comparing `{base[:12]}` → `{head[:12]}`. Evaluation only; no builds.",
        "",
        (
            f"**{sum(map(len, groups.values()))} changed · {len(unchanged)} unchanged · "
            f"{len(failures)} failed** ({len(targets)} configurations checked)."
        ),
        "",
    ]
    for delta, hosts in sorted(groups.items(), key=lambda item: item[1]):
        names = html.escape(", ".join(hosts))
        collapsed = len(delta) > 12 or len(groups) > 3
        if collapsed:
            lines += [
                "<details>",
                f"<summary>{names} — {len(delta)} change(s)</summary>",
                "",
            ]
        else:
            lines += [f"### {names}", ""]
        safe_delta = [
            line.replace("\n", " ").replace("\r", " ").replace("```", "ˋˋˋ")
            for line in delta[:max_lines]
        ]
        lines += ["```diff", *safe_delta, "```"]
        if len(delta) > max_lines:
            lines.append(
                f"Showing {max_lines} of {len(delta)} changes; see the report artifact."
            )
        lines.append("")
        if collapsed:
            lines += ["</details>", ""]
    if unchanged:
        lines += [
            "<details>",
            "<summary>Unchanged configurations</summary>",
            "",
            ", ".join(unchanged),
            "",
            "</details>",
            "",
        ]
    if failures:
        lines += [
            "### Incomplete evaluation",
            "",
            "These configurations could not be compared; they are not reported as unchanged:",
            "",
        ]
        lines += [
            f"- `{host}`: {', '.join(sides)} evaluation failed."
            for host, sides in sorted(failures.items())
        ]
        lines.append("")
    if not targets:
        lines += ["No matching configurations selected.", ""]
    lines += [
        "Covers package names/versions (including Home Manager), kernel versions, and OCI image references from public modules.",
        "Changes to service settings, package contents at the same version, and transitive dependencies are not shown.",
        "",
    ]
    if run_url:
        lines += [f"[Workflow run and full report]({run_url})", ""]
    text = "\n".join(lines)
    # GitHub comments have a size limit independent of per-group line limits.
    if limit_comment and len(text.encode()) > 58000:
        text = "\n".join(lines[:6]) + "\n\nReport exceeds the comment limit. "
        text += f"[Read the full report in the workflow artifacts]({run_url}).\n"
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--host", action="append", default=os.getenv("TARGET_HOSTS", "").split()
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--merge-base",
        action="store_true",
        help="Compare from the PR branch point, excluding later changes on main",
    )
    parser.add_argument(
        "--cache-dir", type=Path, default=Path(".cache/pr-impact/snapshots")
    )
    parser.add_argument(
        "--include-iso", action="store_true", default=os.getenv("INCLUDE_ISO") == "1"
    )
    args = parser.parse_args()
    base = command("git", "rev-parse", "--verify", os.getenv("BASE_SHA") or "HEAD^")
    head = command("git", "rev-parse", "--verify", os.getenv("HEAD_SHA") or "HEAD")
    if args.merge_base:
        base = command("git", "merge-base", base, head)
    files = command(
        "git", "diff", "--name-only", "--no-renames", base, head
    ).splitlines()
    results, failures = {}, defaultdict(list)
    run_url = os.getenv("RUN_URL", "")
    max_lines = max(1, int(os.getenv("MAX_LINES", "80")))
    try:
        with tempfile.TemporaryDirectory(prefix="pr-impact-") as directory:
            roots = {side: Path(directory) / side for side in ("base", "head")}
            configs = {}
            for side, revision in (("base", base), ("head", head)):
                roots[side].mkdir()
                export_revision(revision, roots[side])
                configs[side] = discover(roots[side])
            targets = select_targets(
                configs["base"] | configs["head"], files, args.host, args.include_iso
            )

            def evaluate(target):
                snapshots, errors = [], []
                for side, revision in (("base", base), ("head", head)):
                    if target not in configs[side]:
                        snapshots.append(None)
                        continue
                    try:
                        snapshots.append(
                            snapshot(roots[side], revision, target, args.cache_dir)
                        )
                    except (subprocess.CalledProcessError, ValueError, OSError) as error:
                        errors.append(side)
                        snapshots.append(None)
                        print(f"Evaluation failed: {side} {target}", file=sys.stderr)
                        # Keep the log useful without dumping a whole trace.
                        detail = (getattr(error, "stderr", None) or str(error)).strip()
                        for line in detail.splitlines()[-15:]:
                            print(f"  {line[:300]}", file=sys.stderr)
                return target, snapshots, errors

            with ThreadPoolExecutor(max_workers=2) as workers:
                for target, snapshots, errors in workers.map(evaluate, targets):
                    results[target] = snapshots
                    if errors:
                        failures[target] = errors
            report = render(base, head, targets, results, failures, max_lines, run_url)
            full_report = render(
                base, head, targets, results, failures, sys.maxsize, run_url, False
            )
            details = {
                "base": base,
                "head": head,
                "results": results,
                "failures": failures,
            }
    except (subprocess.CalledProcessError, ValueError, OSError) as error:
        print(f"Report generation failed: {type(error).__name__}", file=sys.stderr)
        report = (
            f"{MARKER}\n## Configuration impact\n\n"
            f"Could not compare `{base[:12]}` → `{head[:12]}`. "
            "Configuration discovery or target selection failed; no clean comparison is available.\n"
        )
        full_report = report
        details = {"base": base, "head": head, "error": type(error).__name__}
        failures["discovery"] = ["base/head"]
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report)
        args.output.with_suffix(".json").write_text(json.dumps(details, indent=2))
        args.output.with_suffix(".full.md").write_text(full_report)
    else:
        print(report)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
