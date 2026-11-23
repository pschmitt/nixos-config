"""Schedule package snapshots for the Nix inputs a consumer actually locks."""
import argparse
import hashlib
import io
import json
import logging
import re
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

LOG = logging.getLogger(__name__)
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
REVISION = re.compile(r"[a-f0-9]{40}")
ATTRIBUTE = re.compile(r"[a-zA-Z0-9_.+-]{1,96}")
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+?=-]+")
WORKFLOW = "circus-consumer-publish.yml"
SYSTEMS = {"aarch64-linux": ("main-arm", "gha-aarch64-linux")}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def revision(repository, ref):
    command = ["git", "ls-remote", "--exit-code", f"https://github.com/{repository}.git", f"refs/heads/{ref}"]
    sha = subprocess.check_output(command, text=True, timeout=30).split("\t", 1)[0]
    if not REVISION.fullmatch(sha):
        raise ValueError(f"Could not resolve {repository} {ref}")
    return sha


def read_consumer_lock(repository, sha):
    url = f"https://raw.githubusercontent.com/{repository}/{sha}/flake.lock"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def nix_json(*args):
    return json.loads(subprocess.check_output(["nix", *args], timeout=180))


def follow(lock, edge, seen=()):
    """Resolve lock-file follows, which always start at the original root."""
    if isinstance(edge, str):
        return edge
    path = tuple(edge)
    if path in seen:
        raise ValueError("Cyclic follows in flake lock")
    node = lock["root"]
    for name in path:
        node = follow(lock, lock["nodes"][node]["inputs"][name], (*seen, path))
    return node


def wrapper_lock(producer, consumer, producer_input, overrides):
    producer_lock = producer["locks"]
    nodes = {"root": {"inputs": {"producer": "producer"}}}
    aliases = nodes["root"]["inputs"]
    consumer_sources = consumer["nodes"][consumer["root"]]["inputs"]
    consumer_producer = consumer["nodes"][follow(consumer, consumer_sources[producer_input])]
    consumer_edges = consumer_producer["inputs"]
    consumer_names = {}
    producer_names = {producer_lock["root"]: "producer"}

    def copy_node(lock, old_name, names, prefix):
        if old_name in names:
            return names[old_name]
        new_name = f"{prefix}-{len(names)}"
        names[old_name] = new_name
        old = lock["nodes"][old_name]
        node = {key: value for key, value in old.items() if key != "inputs"}
        nodes[new_name] = node
        if "inputs" in old:
            edges = {}
            for name, edge in sorted(old["inputs"].items()):
                if prefix == "producer" and isinstance(edge, list):
                    # Producer follows must resolve after consumer overrides.
                    edges[name] = ["producer", *edge]
                else:
                    edges[name] = copy_node(lock, follow(lock, edge), names, prefix)
            node["inputs"] = edges
        return new_name

    root = producer_lock["nodes"][producer_lock["root"]]
    producer_edges = {}
    for name, edge in sorted(root["inputs"].items()):
        if name in overrides:
            old_name = follow(consumer, consumer_edges[name])
            alias = f"consumer-{name}"
            aliases[alias] = copy_node(consumer, old_name, consumer_names, "locked")
            producer_edges[name] = [alias]
        elif isinstance(edge, list):
            producer_edges[name] = ["producer", *edge]
        else:
            producer_edges[name] = copy_node(producer_lock, edge, producer_names, "producer")
    if set(overrides) - root["inputs"].keys():
        raise ValueError("An overridden input is missing from the producer")
    nodes["producer"] = {
        "locked": {key: value for key, value in producer["locked"].items() if key != "__final"},
        "original": producer["original"],
        "inputs": producer_edges,
    }
    return {"nodes": nodes, "root": "root", "version": 7}


def nix_value(value):
    if isinstance(value, dict):
        return "{ " + "".join(f"{nix_value(key)} = {nix_value(item)}; " for key, item in sorted(value.items())) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).replace("${", "\\${")
    if type(value) in (int, bool):
        return json.dumps(value)
    raise ValueError("Unexpected flake input field")


def wrapper_flake(lock, system, packages):
    nodes = lock["nodes"]
    lines = ["{", '  description = "Circus consumer packages";']
    overrides = {
        name: {"follows": edge[0]}
        for name, edge in nodes["producer"]["inputs"].items()
        if isinstance(edge, list) and len(edge) == 1 and edge[0].startswith("consumer-")
    }
    for name, node in sorted(nodes["root"]["inputs"].items()):
        spec = nodes[node]["original"]
        if not nodes[node].get("flake", True):
            spec = {**spec, "flake": False}
        if name == "producer":
            spec = {**spec, "inputs": overrides}
        lines.append(f"  inputs.{nix_value(name)} = {nix_value(spec)};")
    lines.append("  outputs = { producer, ... }: {")
    for package in packages:
        attr = nix_value(package)
        lines.append(f"    circusJobs.{attr} = producer.packages.{nix_value(system)}.{attr};")
    return "\n".join([*lines, "  };", "}", ""]).encode()


def normalize_lock(flake, lock):
    # Nix assigns distinct nodes when an explicitly declared top-level input
    # and a transitive input share the same lock. Preserve their resolved pins.
    with tempfile.TemporaryDirectory(prefix="circus-consumer-") as directory:
        path = Path(directory)
        (path / "flake.nix").write_bytes(flake)
        (path / "flake.lock").write_bytes(canonical(lock))
        metadata = nix_json("flake", "metadata", "--json", "--no-write-lock-file", f"path:{path}")
    normalized = metadata["locks"]

    todo = [(lock["root"], normalized["root"])]
    checked = set()
    while todo:
        left, right = todo.pop()
        pair = (left, right)
        if pair in checked:
            continue
        checked.add(pair)
        source = lock["nodes"][left]
        result = normalized["nodes"][right]
        source_inputs = source.get("inputs", {})
        result_inputs = result.get("inputs", {})
        same_source = source.get("locked") == result.get("locked")
        same_kind = source.get("flake", True) == result.get("flake", True)
        if not (same_source and same_kind and source_inputs.keys() == result_inputs.keys()):
            raise ValueError("Nix changed a pinned input while normalizing the lock")
        todo.extend(
            (follow(lock, edge), follow(normalized, result_inputs[name]))
            for name, edge in source_inputs.items()
        )
    return normalized


def archive_snapshot(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tar:
        for name, content in sorted(files.items()):
            entry = tarfile.TarInfo(name)
            entry.size = len(content)
            entry.mode = 0o644
            tar.addfile(entry, io.BytesIO(content))
    return buffer.getvalue()


def validate_declaration(declaration, consumer_repository):
    if declaration["repository"] != consumer_repository or declaration["ref"] != "main":
        raise ValueError("Only the configured consumer main branch is allowed")
    names = [declaration["input"], *declaration["follows"]]
    if not all(isinstance(name, str) and ATTRIBUTE.fullmatch(name) for name in names):
        raise ValueError("Invalid input name in declaration")
    if "nixpkgs" not in declaration["follows"]:
        raise ValueError("Consumer build must follow nixpkgs")
    for system, packages in declaration["packages"].items():
        if system not in SYSTEMS or not packages or len(packages) > 16:
            raise ValueError("Unsupported consumer system or package count")
        if not all(isinstance(name, str) and ATTRIBUTE.fullmatch(name) for name in packages):
            raise ValueError("Invalid package name")


def plans(repository, producer_sha, consumer_repo, consumer_sha):
    source = f"github:{repository}/{producer_sha}"
    declarations = nix_json("eval", "--json", "--no-write-lock-file", f"{source}#circus.consumerBuilds")
    if not isinstance(declarations, dict):
        raise ValueError("Expected a consumer-build attribute set")
    consumer = read_consumer_lock(consumer_repo, consumer_sha)
    producer = nix_json("flake", "metadata", "--json", "--no-write-lock-file", source)
    for name, declaration in sorted(declarations.items()):
        if not ATTRIBUTE.fullmatch(name) or name in {".", ".."}:
            raise ValueError("Invalid consumer build name")
        validate_declaration(declaration, consumer_repo)
        lock = wrapper_lock(producer, consumer, declaration["input"], declaration["follows"])
        for system, packages in sorted(declaration["packages"].items()):
            packages = sorted(set(packages))
            flake = wrapper_flake(lock, system, packages)
            fingerprint = hashlib.sha256(canonical(lock) + b"\0" + flake).hexdigest()
            metadata = {
                "repository": repository,
                "revision": producer_sha,
                "consumer": consumer_repo,
                "consumer_revision": consumer_sha,
                "system": system,
                "packages": packages,
                "fingerprint": fingerprint,
            }
            yield name, system, fingerprint, flake, lock, metadata


def snapshot_files(flake, lock, metadata):
    return {
        "flake.nix": flake,
        "flake.lock": canonical(normalize_lock(flake, lock)),
        "consumer-build.json": canonical(metadata),
    }


def api(base, token, path, data=None):
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/x-tar"
    request = urllib.request.Request(f"{base.rstrip('/')}/api/v1/{path}", data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def page_items(base, token, path, **filters):
    offset = 0
    while True:
        query = urllib.parse.urlencode({"offset": offset, "limit": 100, **filters})
        page = api(base, token, f"{path}?{query}")
        if isinstance(page, list):
            yield from page
            return
        items = page["items"]
        yield from items
        offset += len(items)
        if not items or offset >= page["total"]:
            return


def ready_outputs(base, token, evaluation_id, system, packages):
    evaluation = api(base, token, f"evaluations/{evaluation_id}")
    if evaluation["status"] in {"pending", "running"}:
        return None
    if evaluation["status"] != "completed" or evaluation.get("error_message"):
        raise ValueError(f"Circus evaluation {evaluation_id} failed")
    builds = {
        build["job_name"]: build
        for build in page_items(base, token, "builds", evaluation_id=evaluation_id)
        if not build["job_name"].startswith("drv:")
    }
    if builds.keys() != set(packages):
        raise ValueError(f"Circus evaluation {evaluation_id} returned different packages")
    if any(build["status"] in {"pending", "running", "queued"} for build in builds.values()):
        return None
    paths = {}
    for package, build in builds.items():
        if build["status"] != "succeeded" or build["system"] != system:
            raise ValueError(f"Circus build for {package} failed in {evaluation_id}")
        outputs = build.get("outputs")
        if not outputs or any(not STORE_PATH.fullmatch(path) for path in outputs.values()):
            raise ValueError(f"Missing or invalid store paths for {package}")
        paths.update({f"{package}.{name}": path for name, path in outputs.items()})
    return paths


def github(base, token, path, payload=None):
    request = urllib.request.Request(
        f"{base}/{path}",
        data=None if payload is None else canonical(payload),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "circus-consumer-builds",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else None


def publish(args, token, receipt, key, metadata):
    if receipt.get("published"):
        return
    evaluation = receipt["evaluation"]
    outputs = ready_outputs(args.api, token, evaluation, metadata["system"], metadata["packages"])
    if outputs is None:
        return
    workflow = f"actions/workflows/{WORKFLOW}"
    github_base = f"https://api.github.com/repos/{args.consumer}"
    github_token = args.github_token_file.read_text().strip()
    title = f"Circus consumer cache {evaluation}"
    runs = github(github_base, github_token, f"{workflow}/runs?event=workflow_dispatch&branch=main&per_page=100")
    run = next((run for run in runs["workflow_runs"] if run["display_title"] == title), None)
    if run is None:
        github(github_base, github_token, f"{workflow}/dispatches", {
            "ref": "main",
            "inputs": {
                "evaluation": evaluation,
                "cache_url": args.cache_url,
                "cache_key": args.cache_key,
                "pin_group": key[:24],
                "outputs": canonical(outputs).decode(),
            },
        })
        LOG.info("Dispatched Niks3 publication for evaluation %s", evaluation)
        return
    if run["status"] != "completed":
        return
    if run["conclusion"] == "success":
        receipt["published"] = run["html_url"]
        LOG.info("Published Circus evaluation %s to Niks3: %s", evaluation, run["html_url"])
        return
    if run["run_attempt"] == 1:
        github(github_base, github_token, f"actions/runs/{run['id']}/rerun", {})
        return
    raise ValueError(f"Niks3 publication failed for {evaluation}: {run['html_url']}")


def save_receipt(path, receipt):
    temp = path.with_suffix(".tmp")
    temp.write_bytes(canonical(receipt))
    temp.replace(path)


def schedule(args):
    token = args.api_token_file.read_text().strip()
    consumer_sha = revision(args.consumer, "main")
    projects = {
        project["repository_url"].rstrip("/"): project["id"]
        for project in page_items(args.api, token, "projects")
    }
    failures = False
    for producer in args.repository:
        try:
            producer_sha = revision(producer, "main")
            project_id = projects[f"https://github.com/{producer}"]
            jobsets = {
                jobset["name"]: jobset["id"]
                for jobset in page_items(args.api, token, f"projects/{project_id}/jobsets")
            }
            for name, system, fingerprint, flake, lock, metadata in plans(producer, producer_sha, args.consumer, consumer_sha):
                key = hashlib.sha256(canonical([producer, name, system])).hexdigest()
                path = args.state_dir / f"{key}.json"
                receipt = json.loads(path.read_bytes()) if path.exists() else {}
                if receipt.get("fingerprint") != fingerprint:
                    jobset, pool = SYSTEMS[system]
                    query = urllib.parse.urlencode({
                        "jobset_id": jobsets[jobset], "flake_jobs": "true",
                        "normal_priority": "true", "pool": pool,
                    })
                    archive = archive_snapshot(snapshot_files(flake, lock, metadata))
                    evaluation = api(args.api, token, f"evaluations/snapshot?{query}", archive)
                    receipt = {"fingerprint": fingerprint, "evaluation": evaluation["id"]}
                    save_receipt(path, receipt)
                    LOG.info("%s %s queued as evaluation %s", producer, system, evaluation["id"])
                if args.github_token_file and not receipt.get("published"):
                    publish(args, token, receipt, key, metadata)
                    if receipt.get("published"):
                        save_receipt(path, receipt)
        except (KeyError, OSError, ValueError, subprocess.SubprocessError) as error:
            LOG.error("Consumer build scheduling failed for %s: %s", producer, error)
            failures = True
    return int(failures)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", action="append", required=True)
    parser.add_argument("--consumer", default="pschmitt/nixos-config")
    parser.add_argument("--api", default="http://127.0.0.1:3000")
    parser.add_argument("--api-token-file", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--github-token-file", type=Path)
    parser.add_argument("--cache-url")
    parser.add_argument("--cache-key")
    parser.add_argument("--plan", type=Path, help="Write one plan for inspection and exit")
    parser.add_argument("--producer-revision")
    parser.add_argument("--consumer-revision")
    args = parser.parse_args()
    if not all(REPOSITORY.fullmatch(repo) for repo in [args.consumer, *args.repository]):
        parser.error("Invalid repository")
    for sha in [args.producer_revision, args.consumer_revision]:
        if sha and not REVISION.fullmatch(sha):
            parser.error("Invalid revision")
    if args.plan:
        if len(args.repository) != 1:
            parser.error("--plan requires one producer")
        producer = args.repository[0]
        producer_sha = args.producer_revision or revision(producer, "main")
        consumer_sha = args.consumer_revision or revision(args.consumer, "main")
        for name, system, _, flake, lock, metadata in plans(producer, producer_sha, args.consumer, consumer_sha):
            directory = args.plan / name / system
            directory.mkdir(parents=True, exist_ok=True)
            for filename, content in snapshot_files(flake, lock, metadata).items():
                (directory / filename).write_bytes(content)
        return 0
    if not args.state_dir or not args.api_token_file:
        parser.error("Scheduling requires --state-dir and --api-token-file")
    publish_options = [args.github_token_file, args.cache_url, args.cache_key]
    if any(publish_options) and not all(publish_options):
        parser.error("Publishing requires --github-token-file, --cache-url and --cache-key")
    return schedule(args)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    raise SystemExit(main())
