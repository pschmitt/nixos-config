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
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "Content-Type": "application/json"},
        method="GET" if data is None else "POST",
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        if response.status == 204:
            return None
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


def project_outputs(get, revision, project_name="stricknani", pr_number=None, jobset_names=("main", "main-arm")):
    """Return successful package outputs from the requested jobsets, or None while pending."""
    project = next(p for p in items(get, "projects") if p["name"] == project_name)
    jobsets = {j["name"]: j for j in items(get, f"projects/{project['id']}/jobsets")}
    outputs = {}
    for jobset in jobset_names:
        if jobset not in jobsets:
            raise ValueError(f"missing Circus jobset {jobset}")
        evaluations = items(get, "evaluations", jobset_id=jobsets[jobset]["id"])
        evaluation = next((e for e in evaluations if e["commit_hash"] == revision and e.get("pr_number") == pr_number), None)
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


def github_status(repository, revision, token_file, state, description, *, context="circus/artifacts"):
    token = Path(token_file).read_text().strip()
    request(
        f"https://api.github.com/repos/{repository}/statuses/{revision}", token,
        {"state": state, "context": context, "description": description},
    )


def author_ids(path):
    values = json.loads(Path(path).read_text())
    if not isinstance(values, list) or not values or any(not isinstance(n, int) or isinstance(n, bool) or n < 1 for n in values):
        raise ValueError("invalid trusted PR author list")
    return set(values)


def trusted_pull_request(pr, repository, allowed_authors):
    """Only run trusted same-repository PR code with cache access."""
    number = pr.get("number")
    author = (pr.get("user") or {}).get("id")
    head = pr.get("head") or {}
    source = head.get("repo") or {}
    return all([
        pr.get("state") == "open",
        pr.get("draft") is False,
        isinstance(author, int) and not isinstance(author, bool) and author in allowed_authors,
        (pr.get("base") or {}).get("ref") == "main",
        source.get("full_name") == repository,
        isinstance(number, int) and not isinstance(number, bool) and number > 0,
        isinstance(head.get("ref"), str) and bool(head["ref"]) and len(head["ref"]) <= 255,
        isinstance(head.get("sha"), str) and SHA.fullmatch(head["sha"]) is not None,
    ])


def pull_request(repository, number, token_file):
    token = Path(token_file).read_text().strip()
    return request(f"https://api.github.com/repos/{repository}/pulls/{number}", token)


def source_is_current(repository, revision, pr_number, token_file, author_file=None):
    if pr_number is None:
        return branch_head(repository) == revision
    pr = pull_request(repository, pr_number, token_file)
    return trusted_pull_request(pr, repository, author_ids(author_file)) and pr["number"] == pr_number and pr["head"]["sha"] == revision


def publish_outputs(paths, repository, revision, pr_number=None, token_file=None, author_file=None):
    """Runs inside nix shell, which keeps all outputs rooted during upload."""
    info = subprocess.Popen(["nix", "--extra-experimental-features", "nix-command", "path-info", "--recursive", *paths.values()], stdout=subprocess.PIPE)
    assert info.stdout is not None
    push = subprocess.run(["niks3", "push", "--stdin"], stdin=info.stdout, check=False)
    info.stdout.close()
    if info.wait() != 0 or push.returncode != 0:
        raise RuntimeError("Niks3 closure upload failed")
    if not source_is_current(repository, revision, pr_number, token_file, author_file):
        raise RuntimeError("source advanced during artifact upload")
    for name, path in sorted(paths.items()):
        safe_name = re.sub(r"[^A-Za-z0-9_-]", "-", name)[:60]
        suffix = hashlib.sha256(name.encode()).hexdigest()[:12]
        project_name = repository.split("/", 1)[1]
        scope = f"-pr-{pr_number}" if pr_number is not None else ""
        subprocess.run(["niks3", "push", "--pin", f"circus-{project_name}{scope}-{safe_name}-{suffix}", path], check=True)


def copy_outputs(paths, repository, revision, secret_file, runtime_dir, pr_number=None, token_file=None, author_file=None):
    project_name = repository.split("/", 1)[1]
    scope = "-pr" if pr_number is not None else ""
    entry = json.loads(Path(secret_file).read_text())[f"niks3-{project_name}{scope}-publisher"]
    expected = False if pr_number is not None else {"and": ["isDefaultBranch", {"isOwner": "pschmitt"}, {"isRepo": project_name}]}
    if (pr_number is not None and entry.get("condition") is not False) or (
        pr_number is None and entry.get("condition") != expected
    ):
        raise ValueError("bridge credential is not scoped to this source")
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
            repository, revision, json.dumps(paths), str(pr_number or 0), token_file or "", str(author_file or ""),
        ], check=True, env=env)


def dispatch_pr_consumers(args, revision, pr_number):
    """Sequence PR consumers without occupying a GitHub runner while waiting."""

    def marker_for(workflow):
        return args.state_dir / f"pr-{pr_number}-{revision}-{workflow}.dispatched"

    state_file = args.state_dir / f"pr-{pr_number}-{revision}.checks-state"
    if state_file.exists() and state_file.read_text().strip() == "success":
        return
    token = Path(args.github_token_file).read_text().strip()
    statuses = request(f"https://api.github.com/repos/{args.repository}/commits/{revision}/status", token)
    if not any(item.get("context") == "circus/pr-artifacts" and item.get("state") == "success"
               for item in statuses.get("statuses", [])):
        return
    pr = pull_request(args.repository, pr_number, args.github_token_file)
    if not trusted_pull_request(pr, args.repository, author_ids(args.pr_author_ids_file)) or pr["number"] != pr_number or pr["head"]["sha"] != revision:
        return

    def report(state, description):
        if not state_file.exists() or state_file.read_text().strip() != state:
            github_status(args.repository, revision, args.github_token_file, state, description, context="circus/pr-checks")
            state_file.write_text(state + "\n")

    def dispatch(workflow):
        inputs = {"circus_pr_number": str(pr_number), "circus_pr_sha": revision}
        if workflow == "e2e.yaml":
            inputs["lane"] = "smoke"
        request(
            f"https://api.github.com/repos/{args.repository}/actions/workflows/{workflow}/dispatches",
            token, {"ref": "main", "inputs": inputs},
        )
        marker_for(workflow).touch()

    def result(workflow, title):
        runs = request(
            f"https://api.github.com/repos/{args.repository}/actions/workflows/{workflow}/runs?event=workflow_dispatch&branch=main&per_page=100",
            token,
        ).get("workflow_runs", [])
        matching = next((run for run in runs if all([
            run.get("event") == "workflow_dispatch",
            run.get("head_branch") == "main",
            run.get("display_title") == f"{title} {revision}",
        ])), None)
        if not matching or matching.get("status") != "completed":
            return "pending"
        return "success" if matching.get("conclusion") == "success" else "failure"

    if not marker_for("build.yaml").exists():
        if args.repository == "pschmitt/declaroid":
            workflow = "e2e.yml"
            if not marker_for(workflow).exists():
                report("pending", "Waiting for PR end-to-end checks")
                dispatch(workflow)
                return
            e2e_result = result(workflow, "Circus PR E2E")
            report(e2e_result, "PR end-to-end checks " + e2e_result)
            return
        report("pending", "Waiting for PR artifact checks")
        dispatch("build.yaml")
        return
    build_result = result("build.yaml", "Circus PR artifacts")
    if build_result != "success":
        report(build_result, "PR artifact build checks " + build_result)
        return
    if not marker_for("e2e.yaml").exists():
        report("pending", "Waiting for PR end-to-end checks")
        dispatch("e2e.yaml")
        return
    e2e_result = result("e2e.yaml", "Circus PR E2E")
    report(e2e_result, "PR end-to-end checks " + e2e_result)


def reconcile_source(args, get, revision, pr_number=None):
    prefix = f"pr-{pr_number}-" if pr_number is not None else ""
    context = "circus/pr-artifacts" if pr_number is not None else "circus/artifacts"
    receipt = args.state_dir / f"{prefix}{revision}.json"
    if receipt.exists():
        if pr_number is not None:
            dispatch_pr_consumers(args, revision, pr_number)
        return
    pending = args.state_dir / f"{prefix}{revision}.pending"
    failed = args.state_dir / f"{prefix}{revision}.failed"
    if not pending.exists():
        github_status(args.repository, revision, args.github_token_file, "pending", "Waiting for Circus artifacts", context=context)
        pending.touch()
    try:
        paths = project_outputs(get, revision, args.repository.split("/", 1)[1], pr_number, getattr(args, "jobsets", ("main", "main-arm")))
    except BuildFailed as error:
        if not failed.exists():
            github_status(args.repository, revision, args.github_token_file, "failure", str(error), context=context)
            failed.touch()
        return
    if paths is None:
        return
    author_file = args.pr_author_ids_file if pr_number is not None else None
    copy_outputs(paths, args.repository, revision, args.secrets_file, args.runtime_dir, pr_number, args.github_token_file, author_file)
    if not source_is_current(args.repository, revision, pr_number, args.github_token_file, author_file):
        return
    github_status(args.repository, revision, args.github_token_file, "success", "Circus artifacts are in Niks3", context=context)
    receipt.write_text(json.dumps({"revision": revision, "outputs": len(paths)}) + "\n")
    pending.unlink(missing_ok=True)
    failed.unlink(missing_ok=True)
    if pr_number is not None:
        dispatch_pr_consumers(args, revision, pr_number)


def reconcile(args):
    api_token = Path(args.api_token_file).read_text().strip()

    def get(path, **params):
        url = args.api.rstrip("/") + "/api/v1/" + path
        return request(url + "?" + urllib.parse.urlencode(params), api_token)

    reconcile_source(args, get, branch_head(args.repository))
    if args.repository != "pschmitt/stricknani":
        return
    token = Path(args.github_token_file).read_text().strip()
    allowed_authors = author_ids(args.pr_author_ids_file)
    page = 1
    while True:
        prs = request(f"https://api.github.com/repos/{args.repository}/pulls?state=open&per_page=100&page={page}", token)
        if not isinstance(prs, list):
            raise ValueError("GitHub PR listing was not a list")
        for pr in prs:
            if trusted_pull_request(pr, args.repository, allowed_authors):
                try:
                    reconcile_source(args, get, pr["head"]["sha"], pr["number"])
                except Exception:
                    LOG.exception("PR %s artifact reconciliation failed; will retry", pr["number"])
        if len(prs) < 100:
            return
        page += 1


def main():
    if len(sys.argv) == 8 and sys.argv[1] == "--publish":
        number = int(sys.argv[5])
        publish_outputs(json.loads(sys.argv[4]), sys.argv[2], sys.argv[3], number or None, sys.argv[6], sys.argv[7])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default="pschmitt/stricknani")
    parser.add_argument("--api", required=True)
    parser.add_argument("--api-token-file", required=True)
    parser.add_argument("--github-token-file", required=True)
    parser.add_argument("--secrets-file", required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--pr-author-ids-file", type=Path)
    parser.add_argument("--jobset", dest="jobsets", action="append")
    args = parser.parse_args()
    args.jobsets = args.jobsets or ["main", "main-arm"]
    if args.repository not in {"pschmitt/stricknani", "pschmitt/monarch", "pschmitt/circus", "pschmitt/declaroid"}:
        raise ValueError("the bridge is restricted to configured repositories")
    if args.repository in {"pschmitt/stricknani", "pschmitt/declaroid"} and args.pr_author_ids_file is None:
        raise ValueError("the PR bridge requires the trusted PR author list")
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
