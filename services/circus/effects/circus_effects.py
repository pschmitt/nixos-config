"""Publish current branch artifacts independently as Circus caches them.

The publisher uses nixbot's sandbox and secrets format and respects each
effect's dependencies, lock and when.changed metadata. Dry runs only log
which effects are ready. The legacy webhook mode is available for callers
that need an evaluation-wide trigger.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import hmac
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

log = logging.getLogger("circus-effects")

SIGNATURE_HEADER = "X-Circus-Signature"
MAX_BODY = 64 * 1024


@dataclass(frozen=True)
class Settings:
    state_dir: Path
    secret_key: bytes
    project: str
    jobset: str
    branch: str
    repository: str  # owner/repo on GitHub
    nbo: str = "nbo"
    secrets_file: Path | None = None
    dry_run: bool = True
    status_token_file: Path | None = None
    status_dir: Path | None = None
    cache_url: str | None = None

    @property
    def queue_dir(self) -> Path:
        return self.state_dir / "queue"

    @property
    def done_dir(self) -> Path:
        return self.state_dir / "done"

    @property
    def changed_dir(self) -> Path:
        return self.state_dir / "changed"

    @property
    def lock_dir(self) -> Path:
        return self.state_dir / "locks"


@dataclass(frozen=True)
class Effect:
    name: str
    after: tuple[str, ...] = ()
    lock: str | None = None
    changed: dict[str, str] | None = None


@dataclass
class Outcome:
    ran: list[str] = field(default_factory=list)
    skipped: dict[str, str] = field(default_factory=dict)
    failed: list[str] = field(default_factory=list)


def valid_signature(secret: bytes, body: bytes, header: str | None) -> bool:
    """Check Circus' `X-Circus-Signature: sha256=<hex>` header."""
    if not header or not header.startswith("sha256="):
        return False
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header.removeprefix("sha256="))


def gate(event: dict[str, Any], settings: Settings, head: str | None) -> str | None:
    """Why this event must not run effects, or None if it may.

    `head` is the branch's current commit (from `git ls-remote`), checked
    right before running so a newer push wins over an older green build.
    """
    if event.get("event") != "evaluation_finished":
        return f"not an evaluation event ({event.get('event')!r})"
    if event.get("status") != "success":
        return f"evaluation status is {event.get('status')!r}"
    if event.get("pr_number") is not None:
        return f"pull request #{event['pr_number']}"
    if event.get("superseded_by"):
        return "superseded by a newer evaluation"
    if event.get("project_name") != settings.project:
        return f"project {event.get('project_name')!r}"
    if event.get("jobset_name") != settings.jobset:
        return f"jobset {event.get('jobset_name')!r}"
    if event.get("branch") != settings.branch:
        return f"branch {event.get('branch')!r}"
    commit = event.get("commit_hash")
    if not commit:
        return "no commit"
    if head is None:
        return f"cannot resolve the head of {settings.branch}"
    if commit != head:
        return f"{commit[:12]} is no longer the head of {settings.branch} ({head[:12]})"
    return None


def order(effects: dict[str, Effect]) -> list[str]:
    """Effects in an order that respects `after` (dependencies first)."""
    done: list[str] = []
    seen: set[str] = set()

    def visit(name: str, chain: tuple[str, ...]) -> None:
        if name in seen:
            return
        if name in chain:
            msg = f"effect dependency cycle: {' -> '.join((*chain, name))}"
            raise ValueError(msg)
        for dep in effects[name].after:
            if dep not in effects:
                msg = f"{name} runs after unknown effect {dep}"
                raise ValueError(msg)
            visit(dep, (*chain, name))
        seen.add(name)
        done.append(name)

    for name in sorted(effects):
        visit(name, ())
    return done


def unchanged(effect: Effect, changed_dir: Path) -> bool:
    """`when.changed`: true if the declared inputs equal the last success's."""
    if not effect.changed:
        return False
    try:
        last = json.loads((changed_dir / f"{effect.name}.json").read_text())
    except (OSError, ValueError):
        return False
    return last == effect.changed


def record_success(effect: Effect, changed_dir: Path) -> None:
    if not effect.changed:
        return
    changed_dir.mkdir(parents=True, exist_ok=True)
    changed_dir.chmod(0o700)
    atomic_write(changed_dir / f"{effect.name}.json", json.dumps(effect.changed))


def write_status(settings: Settings, commit: str, effects: dict[str, tuple[str, str]]) -> None:
    """Write the small, read-only summary consumed by the build dashboard."""
    if settings.status_dir is None:
        return
    if settings.status_dir.is_symlink():
        log.warning("refusing to write effect status through a symlink")
        return
    settings.status_dir.mkdir(parents=True, exist_ok=True, mode=0o750)
    if not settings.status_dir.is_dir() or settings.status_dir.is_symlink():
        log.warning("refusing to write effect status outside its directory")
        return
    settings.status_dir.chmod(0o750)
    target = settings.status_dir / f"{commit}.json"
    atomic_write(
        target,
        json.dumps(
            {
                "commit": commit,
                "updated_at": int(time.time()),
                "effects": [
                    {"name": name, "state": state, "message": message}
                    for name, (state, message) in sorted(effects.items())
                ],
            }
        ),
    )
    target.chmod(0o640)
    snapshots = sorted(
        settings.status_dir.glob("[0-9a-f]*.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for stale in snapshots[10:]:
        stale.unlink(missing_ok=True)


def atomic_write(target: Path, text: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    Path(tmp).replace(target)


class EffectLock:
    """An exclusive `flock` on <lock_dir>/<name>.lock, held for one effect."""

    def __init__(self, lock_dir: Path, name: str | None) -> None:
        self.path = lock_dir / f"{name}.lock" if name else None
        self.fd: int | None = None

    def __enter__(self) -> EffectLock:
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_exc: object) -> None:
        if self.fd is not None:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            os.close(self.fd)


def branch_head(repository: str, branch: str) -> str | None:
    url = f"https://github.com/{repository}"
    try:
        out = subprocess.run(
            ["git", "ls-remote", url, f"refs/heads/{branch}"],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        ).stdout
    except (subprocess.SubprocessError, OSError) as e:
        log.warning("git ls-remote %s failed: %s", url, e)
        return None
    return out.split()[0] if out.strip() else None


def list_effects(settings: Settings, flake_ref: str) -> dict[str, Effect]:
    out = subprocess.run(
        [settings.nbo, "effects", "list", flake_ref],
        check=True,
        capture_output=True,
        text=True,
        timeout=1800,
    ).stdout
    effects = {}
    for name, meta in json.loads(out).items():
        effects[name] = Effect(
            name=name,
            after=tuple(meta.get("after") or ()),
            lock=meta.get("lock"),
            changed=meta.get("changed"),
        )
    return effects


def post_status(settings: Settings, commit: str, name: str, state: str, text: str) -> None:
    """A `circus-effects/<name>` commit status, via the GitHub App token."""
    if settings.status_token_file is None:
        return
    try:
        token = settings.status_token_file.read_text().strip()
    except OSError as e:
        log.warning("no GitHub token for statuses: %s", e)
        return
    req = Request(  # noqa: S310 - fixed https URL
        f"https://api.github.com/repos/{settings.repository}/statuses/{commit}",
        data=json.dumps(
            {"state": state, "context": f"circus-effects/{name}", "description": text[:140]}
        ).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=30):  # noqa: S310
            pass
    except OSError as e:
        log.warning("commit status for %s failed: %s", name, e)


def run_one(settings: Settings, effect: Effect, flake_ref: str, commit: str, checkout: Path) -> int:
    cmd = [
        settings.nbo,
        "effects",
        "run",
        "--rev",
        commit,
        "--branch",
        settings.branch,
        "--default-branch",
        settings.branch,
        "--repo",
        settings.repository,
        "--effect-checkout",
        str(checkout),
    ]
    if settings.secrets_file:
        cmd += ["--secrets", str(settings.secrets_file)]
    cmd.append(f"{flake_ref}#{effect.name}")
    result = subprocess.run(cmd, check=False, timeout=6 * 3600)
    return result.returncode


def process(
    event: dict[str, Any],
    settings: Settings,
    effects: dict[str, Effect] | None = None,
    ready: set[str] | None = None,
    states: dict[str, tuple[str, str]] | None = None,
    receipt: Path | None = None,
) -> Outcome:
    """Run (or, in dry-run, list) the effects for one evaluation event."""
    outcome = Outcome()
    if ready is None:
        reason = gate(event, settings, branch_head(settings.repository, settings.branch))
        if reason:
            log.info("evaluation %s: no effects: %s", event.get("evaluation_id"), reason)
            outcome.skipped["*"] = reason
            return outcome

    commit = event["commit_hash"]
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        log.warning("evaluation %s has an invalid commit hash", event.get("evaluation_id"))
        outcome.skipped["*"] = "invalid commit hash"
        return outcome
    flake_ref = f"github:{settings.repository}/{commit}"
    if effects is None:
        effects = list_effects(settings, flake_ref)
    if states is None:
        states = {name: ("pending", "Waiting for the effects runner.") for name in effects}
    write_status(settings, commit, states)
    failed: set[str] = set()
    with tempfile.TemporaryDirectory(prefix="circus-effects-") as tmp:
        checkout = Path(tmp) / "checkout"
        if not settings.dry_run:
            subprocess.run(
                [
                    "git",
                    "clone",
                    "--quiet",
                    "--filter=blob:none",
                    f"https://github.com/{settings.repository}",
                    str(checkout),
                ],
                check=True,
                timeout=600,
            )
            subprocess.run(
                ["git", "-C", str(checkout), "checkout", "--quiet", commit],
                check=True,
                timeout=600,
            )
        for name in order(effects):
            effect = effects[name]
            if ready is not None:
                if states[name][0] in {"success", "dry_run", "skipped", "failed"}:
                    if states[name][0] in {"failed", "skipped"} and states[name][1] != "Inputs are unchanged since the last successful run.":
                        failed.add(name)
                    continue
                if any(states[d][0] in {"pending", "running"} for d in effect.after):
                    continue
                if name not in ready:
                    continue
                if branch_head(settings.repository, settings.branch) != commit:
                    break
            if blocked := [d for d in effect.after if d in failed]:
                outcome.skipped[name] = f"dependency failed: {', '.join(blocked)}"
                failed.add(name)
                states[name] = ("skipped", "An earlier dependency did not succeed.")
                write_status(settings, commit, states)
                if receipt is not None:
                    atomic_write(receipt, json.dumps(states))
                continue
            if unchanged(effect, settings.changed_dir):
                outcome.skipped[name] = "when.changed: inputs unchanged"
                states[name] = ("skipped", "Inputs are unchanged since the last successful run.")
                write_status(settings, commit, states)
                if receipt is not None:
                    atomic_write(receipt, json.dumps(states))
                continue
            if settings.dry_run:
                log.info(
                    "dry-run %s: would run %s (lock=%s, changed=%s)",
                    commit[:12],
                    name,
                    effect.lock,
                    json.dumps(effect.changed, sort_keys=True),
                )
                outcome.ran.append(name)
                states[name] = ("dry_run", "The effect was selected in a dry run.")
                write_status(settings, commit, states)
                if receipt is not None:
                    atomic_write(receipt, json.dumps(states))
                continue
            states[name] = ("running", "The effects runner started processing this effect.")
            write_status(settings, commit, states)
            post_status(settings, commit, name, "pending", "running")
            try:
                with EffectLock(settings.lock_dir, effect.lock):
                    if ready is not None and branch_head(settings.repository, settings.branch) != commit:
                        states[name] = ("pending", "The branch moved before publishing.")
                        break
                    returncode = run_one(settings, effect, flake_ref, commit, checkout)
            except subprocess.TimeoutExpired:
                returncode = None
            if returncode == 0:
                record_success(effect, settings.changed_dir)
                outcome.ran.append(name)
                states[name] = ("success", "The effects runner exited successfully.")
                post_status(settings, commit, name, "success", "effect succeeded")
            else:
                failed.add(name)
                outcome.failed.append(name)
                if returncode is None:
                    message = "The effect exceeded its six-hour execution timeout."
                elif returncode < 0:
                    message = f"The effects runner was terminated by signal {-returncode}."
                else:
                    message = f"The effects runner exited with status {returncode}."
                states[name] = ("failed", message)
                post_status(settings, commit, name, "failure", "effect failed")
            write_status(settings, commit, states)
            if receipt is not None:
                atomic_write(receipt, json.dumps(states))
    for name, why in outcome.skipped.items():
        log.info("%s %s: skipped %s: %s", "dry-run" if settings.dry_run else "run", commit[:12], name, why)
    return outcome


ARTIFACT_JOBS = {
    "publish.standard": "iso",
    "publish.private": "iso-private",
    "publish.standard-legacy": "iso-legacy",
    "publish.private-legacy": "iso-private-legacy",
    "publish.graphical": "iso-graphical",
    "publish.multios": "iso",
    "publish.private-multios": "iso-private",
    "publish.publish-browser-worker-image": "rworker-browser-daemon",
    "publish.publish-nixbot-worker-image": "rworker",
    "publish.publish-circus-worker-image": "rworker-circus",
    "publish.publish-circus-qemu-worker-image": "rworker-circus-qemu",
}


def load_artifacts(flake_ref: str, effects: dict[str, Effect]) -> dict[str, str]:
    jobs = {name: ARTIFACT_JOBS[name] for name in effects}
    result = subprocess.run(
        [
            "nix", "eval", "--json", f"{flake_ref}#circusJobs.images",
            "--apply", f"images: {{ {' '.join(f'{json.dumps(name)} = toString images.{job};' for name, job in jobs.items())} }}",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=1800,
    )
    return json.loads(result.stdout)


def artifact_cached(cache_url: str, path: str) -> bool:
    match = re.fullmatch(r"/nix/store/([0-9a-z]{32})-[^/]+", path)
    if not match:
        raise ValueError("invalid artifact store path")
    try:
        with urlopen(f"{cache_url.rstrip('/')}/{match[1]}.narinfo", timeout=15) as response:
            return f"StorePath: {path}" in response.read(65536).decode().splitlines()
    except OSError:
        return False


def watch_artifacts(settings: Settings) -> None:
    """Reconcile the current branch and resume individual effects after restarts."""
    assert settings.cache_url is not None
    previous = None
    while True:
        try:
            commit = branch_head(settings.repository, settings.branch)
            if commit and re.fullmatch(r"[0-9a-f]{40,64}", commit):
                if commit != previous:
                    flake_ref = f"github:{settings.repository}/{commit}"
                    effects = list_effects(settings, flake_ref)
                    artifacts = load_artifacts(flake_ref, effects)
                    if effects.keys() != artifacts.keys():
                        raise ValueError("publishing effects and artifact prerequisites differ")
                    states = {
                        name: ("pending", "Waiting for the artifact in the Circus cache.") for name in effects
                    }
                    mode = "dry-run" if settings.dry_run else "live"
                    receipt = settings.state_dir / f"artifact-{mode}-{commit}.json"
                    if receipt.exists():
                        for name, state in json.loads(receipt.read_text()).items():
                            if name in states:
                                states[name] = tuple(state)
                    write_status(settings, commit, states)
                    previous = commit
                cached = {
                    path: artifact_cached(settings.cache_url, path)
                    for path in {artifacts[name] for name in effects if states[name][0] in {"pending", "running"}}
                }
                ready = {name for name, path in artifacts.items() if cached.get(path)}
                if ready:
                    process(
                        {"commit_hash": commit},
                        settings,
                        effects,
                        ready,
                        states,
                        receipt,
                    )
        except Exception:
            log.exception("checking publishing prerequisites failed")
        time.sleep(60)


def enqueue(settings: Settings, event: dict[str, Any]) -> bool:
    """Persist an event; False if this evaluation was already handled."""
    eval_id = str(event.get("evaluation_id", ""))
    if not eval_id or "/" in eval_id or eval_id.startswith("."):
        msg = "bad evaluation_id"
        raise ValueError(msg)
    if (settings.done_dir / eval_id).exists() or (settings.queue_dir / f"{eval_id}.json").exists():
        return False
    settings.queue_dir.mkdir(parents=True, exist_ok=True)
    settings.queue_dir.chmod(0o700)
    atomic_write(settings.queue_dir / f"{eval_id}.json", json.dumps(event))
    return True


def worker(settings: Settings, wake: threading.Event) -> None:
    while True:
        wake.wait(timeout=60)
        wake.clear()
        for item in sorted(settings.queue_dir.glob("*.json"), key=lambda p: p.stat().st_mtime):
            try:
                event = json.loads(item.read_text())
                outcome = process(event, settings)
                log.info(
                    "evaluation %s done: ran=%s failed=%s skipped=%d",
                    event.get("evaluation_id"),
                    outcome.ran,
                    outcome.failed,
                    len(outcome.skipped),
                )
            except Exception:
                log.exception("processing %s failed; it stays queued", item.name)
                continue
            settings.done_dir.mkdir(parents=True, exist_ok=True)
            atomic_write(settings.done_dir / item.stem, str(int(time.time())))
            item.unlink(missing_ok=True)


def handler(settings: Settings, wake: threading.Event) -> type[BaseHTTPRequestHandler]:
    class Hook(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802 - http.server API
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > MAX_BODY:
                self.send_error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
                return
            body = self.rfile.read(length)
            if not valid_signature(settings.secret_key, body, self.headers.get(SIGNATURE_HEADER)):
                log.warning("rejected a webhook with a bad signature")
                self.send_error(HTTPStatus.UNAUTHORIZED)
                return
            try:
                event = json.loads(body)
            except ValueError:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            if event.get("event") != "evaluation_finished":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
                return
            try:
                queued = enqueue(settings, event)
            except ValueError:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            log.info("evaluation %s %s", event.get("evaluation_id"), "queued" if queued else "already handled")
            if queued:
                wake.set()
            self.send_response(HTTPStatus.ACCEPTED)
            self.end_headers()

        def log_message(self, fmt: str, *args: object) -> None:
            log.debug(fmt, *args)

    return Hook


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3010)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--secret-file", type=Path, help="HMAC key for webhook mode")
    parser.add_argument("--cache-url", help="Check publishing artifacts in this Circus cache")
    parser.add_argument("--project", required=True)
    parser.add_argument("--jobset", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--repository", required=True, help="GitHub owner/repo")
    parser.add_argument("--nbo", default="nbo")
    parser.add_argument("--secrets-file", type=Path, help="effects secrets.json")
    parser.add_argument("--status-token-file", type=Path)
    parser.add_argument("--status-dir", type=Path)
    parser.add_argument("--run", action="store_true", help="run effects (default: dry-run)")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr)

    settings = Settings(
        state_dir=args.state_dir,
        secret_key=args.secret_file.read_bytes().strip() if args.secret_file else b"",
        project=args.project,
        jobset=args.jobset,
        branch=args.branch,
        repository=args.repository,
        nbo=args.nbo,
        secrets_file=args.secrets_file,
        dry_run=not args.run,
        status_token_file=args.status_token_file,
        status_dir=args.status_dir,
        cache_url=args.cache_url,
    )
    if not settings.cache_url and not settings.secret_key:
        parser.error("the HMAC key file is empty")
    for d in (settings.queue_dir, settings.done_dir, settings.changed_dir, settings.lock_dir):
        d.mkdir(parents=True, exist_ok=True)
        d.chmod(0o700)

    if settings.cache_url:
        watch_artifacts(settings)
        return 0

    wake = threading.Event()
    wake.set()  # drain whatever was queued before a restart
    threading.Thread(target=worker, args=(settings, wake), daemon=True).start()
    server = ThreadingHTTPServer((args.listen, args.port), handler(settings, wake))
    log.info(
        "listening on %s:%d (%s) for %s/%s@%s",
        args.listen,
        args.port,
        "dry-run" if settings.dry_run else "running effects",
        settings.project,
        settings.jobset,
        settings.branch,
    )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
