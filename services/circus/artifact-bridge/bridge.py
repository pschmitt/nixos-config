"""Copy successful, exact-revision Circus outputs into the shared Niks3 cache."""

import argparse
import hashlib
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

LOG = logging.getLogger("circus-artifact-bridge")
SHA = re.compile(r"[0-9a-f]{40}")
STORE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-[^/]+")


class BuildFailed(Exception):
    """The current revision has a failed Circus evaluation or build."""


def request(url, token, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
        method="GET" if data is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def items(get, path, **params):
    offset = 0
    while True:
        result = get(path, limit=100, offset=offset, **params)
        if isinstance(result, list):
            yield from result
            return
        page = result["items"]
        yield from page
        offset += len(page)
        if not page or offset >= result["total"]:
            return


def project_outputs(get, revision):
    """Return successful package outputs from both jobsets, or None while pending."""
    project = next(p for p in items(get, "projects") if p["name"] == "stricknani")
    jobsets = {j["name"]: j for j in items(get, f"projects/{project['id']}/jobsets")}
    outputs = {}
    for jobset in ("main", "main-arm"):
        if jobset not in jobsets:
            raise ValueError(f"missing Circus jobset {jobset}")
        evaluations = items(get, "evaluations", jobset_id=jobsets[jobset]["id"])
        evaluation = next((e for e in evaluations if e["commit_hash"] == revision and e.get("pr_number") is None), None)
        if evaluation is None or evaluation["status"] in {"pending", "running"}:
            return None
        if evaluation["status"] != "completed" or evaluation.get("error_message"):
            raise BuildFailed(f"Circus {jobset} evaluation failed")
        builds = [b for b in items(get, "builds", evaluation_id=evaluation["id"]) if not b["job_name"].startswith("drv:")]
        if not builds or any(b["status"] in {"pending", "running"} for b in builds):
            return None
        if any(b["status"] != "succeeded" for b in builds):
            raise BuildFailed(f"Circus {jobset} build failed")
        packages = [b for b in builds if b["job_name"].startswith("packages.")]
        if not packages:
            raise ValueError(f"Circus {jobset} produced no packages")
        for build in packages:
            package_outputs = build.get("outputs") or {}
            if not package_outputs:
                raise ValueError("Circus package has no output paths")
            for name, path in package_outputs.items():
                if not isinstance(path, str) or not STORE_PATH.fullmatch(path):
                    raise ValueError("invalid Circus output path")
                outputs[f"{jobset}-{build['job_name']}-{name}"] = path
    if not outputs:
        raise ValueError("Circus returned no package output paths")
    return outputs


def branch_head(repository):
    result = subprocess.run(
        ["git", "ls-remote", f"https://github.com/{repository}.git", "refs/heads/main"],
        check=True, capture_output=True, text=True, timeout=60,
    )
    revision = result.stdout.split("\t", 1)[0]
    if not SHA.fullmatch(revision):
        raise ValueError("could not determine main revision")
    return revision


def github_status(repository, revision, token_file, state, description):
    token = Path(token_file).read_text().strip()
    request(
        f"https://api.github.com/repos/{repository}/statuses/{revision}", token,
        {"state": state, "context": "circus/artifacts", "description": description},
    )


def publish_outputs(paths, repository, revision):
    """Runs inside nix shell, which keeps all outputs rooted during upload."""
    info = subprocess.Popen(["nix", "--extra-experimental-features", "nix-command", "path-info", "--recursive", *paths.values()], stdout=subprocess.PIPE)
    assert info.stdout is not None
    push = subprocess.run(["niks3", "push", "--stdin"], stdin=info.stdout, check=False)
    info.stdout.close()
    if info.wait() != 0 or push.returncode != 0:
        raise RuntimeError("Niks3 closure upload failed")
    if branch_head(repository) != revision:
        raise RuntimeError("main advanced during artifact upload")
    for name, path in sorted(paths.items()):
        safe_name = re.sub(r"[^A-Za-z0-9_-]", "-", name)[:60]
        suffix = hashlib.sha256(name.encode()).hexdigest()[:12]
        subprocess.run(["niks3", "push", "--pin", f"circus-stricknani-{safe_name}-{suffix}", path], check=True)


def copy_outputs(paths, repository, revision, secret_file, runtime_dir):
    entry = json.loads(Path(secret_file).read_text())["niks3-stricknani-publisher"]
    expected = {"and": ["isDefaultBranch", {"isOwner": "pschmitt"}, {"isRepo": "stricknani"}]}
    if entry.get("condition") != expected:
        raise ValueError("bridge credential is not scoped to Stricknani main")
    secret = entry["data"]
    with tempfile.NamedTemporaryFile(mode="w", dir=runtime_dir, prefix="niks3-", delete=True) as token:
        os.fchmod(token.fileno(), 0o600)
        token.write(secret["token"])
        token.flush()
        env = {**os.environ, "NIKS3_AUTH_TOKEN_FILE": token.name, "NIKS3_SERVER_URL": secret["server_url"]}
        subprocess.run([
            "nix", "--extra-experimental-features", "nix-command flakes", "shell",
            "--option", "max-jobs", "0", "--option", "builders", "", "--option", "fallback", "false",
            *sorted(set(paths.values())), "--command", sys.executable, __file__, "--publish",
            repository, revision, json.dumps(paths),
        ], check=True, env=env)


def reconcile(args):
    revision = branch_head(args.repository)
    receipt = args.state_dir / f"{revision}.json"
    if receipt.exists():
        return
    pending = args.state_dir / f"{revision}.pending"
    failed = args.state_dir / f"{revision}.failed"
    if not pending.exists():
        github_status(args.repository, revision, args.github_token_file, "pending", "Waiting for Circus artifacts")
        pending.touch()
    api_token = Path(args.api_token_file).read_text().strip()

    def get(path, **params):
        url = args.api.rstrip("/") + "/api/v1/" + path
        return request(url + "?" + urllib.parse.urlencode(params), api_token)

    try:
        paths = project_outputs(get, revision)
    except BuildFailed as error:
        if not failed.exists():
            github_status(args.repository, revision, args.github_token_file, "failure", str(error))
            failed.touch()
        return
    if paths is None:
        return
    copy_outputs(paths, args.repository, revision, args.secrets_file, args.runtime_dir)
    if branch_head(args.repository) != revision:
        return
    github_status(args.repository, revision, args.github_token_file, "success", "Circus artifacts are in Niks3")
    receipt.write_text(json.dumps({"revision": revision, "outputs": len(paths)}) + "\n")
    pending.unlink(missing_ok=True)
    failed.unlink(missing_ok=True)


def main():
    if len(sys.argv) == 5 and sys.argv[1] == "--publish":
        publish_outputs(json.loads(sys.argv[4]), sys.argv[2], sys.argv[3])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default="pschmitt/stricknani")
    parser.add_argument("--api", required=True)
    parser.add_argument("--api-token-file", required=True)
    parser.add_argument("--github-token-file", required=True)
    parser.add_argument("--secrets-file", required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.repository != "pschmitt/stricknani":
        raise ValueError("the bridge is restricted to pschmitt/stricknani")
    args.state_dir.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO)
    while True:
        try:
            reconcile(args)
        except Exception:
            LOG.exception("Artifact reconciliation failed; will retry")
        time.sleep(60)


if __name__ == "__main__":
    main()
