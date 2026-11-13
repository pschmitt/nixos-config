"""MCP server for ad-hoc build workers (rworker).

A thin layer over the `rworker` client (skills/rworker), so host-key
pinning, local state and SSH keys work exactly as on the command line:
create a short-lived encrypted build VM, run commands or long jobs on it,
copy sources over, use it as a Nix builder, and delete it again.
"""

import argparse
import json
import subprocess
import time

from mcp.server.mcpserver import MCPServer

ap = argparse.ArgumentParser()
ap.add_argument("--rworker", required=True, help="path to the rworker client")
args = ap.parse_args()

mcp = MCPServer("rworker")

# Keep tool results small: build logs can be megabytes.
MAX_OUTPUT = 20_000


def tail(text, limit=MAX_OUTPUT):
    if len(text) <= limit:
        return text, False
    return text[-limit:], True


def run(*argv, timeout=900):
    """Run the rworker client; raise with its stderr on failure."""
    proc = subprocess.run(
        [args.rworker, *argv],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        err, _ = tail(proc.stderr.strip() or proc.stdout.strip(), 4000)
        raise RuntimeError(f"rworker {argv[0]} failed: {err}")
    return proc.stdout


@mcp.tool()
def up(
    ttl: str = "2h",
    flavor: str | None = None,
    disk_gib: int | None = None,
    scratch: bool = False,
    topic: str | None = None,
    nix_cache: bool = True,
    profile: str | None = None,
    niks3_token: bool = True,
) -> dict:
    """Create an ad-hoc build worker and wait until it is ready (2-4 min).

    ttl: lifetime such as "90m" or "3h" (default 2h). A worker still in use
    when it expires stays until it has been idle for 1 h, up to its maximum
    lifetime (24 h, or 7 days with scratch=True). topic: ALWAYS set it - a few words on what
    it is for (shown by ls/inspect; the creating agent, its PID, session and
    cwd are recorded automatically). flavor: s1.large (8 vCPU), s1.xlarge (16, default),
    s1.2xlarge (32). profile selects a configured worker profile: standard,
    browser-daemon, or large-builder. Profile defaults can be overridden with
    flavor and disk_gib. disk_gib: volume size (default 150). nix_cache (default
    True) lets the worker substitute from the private S3 Nix cache with this
    host's read-only credentials (pushed over SSH, only if this host has an
    s3:// substituter); pass False to keep the key off the worker. The result
    then has a nix_cache object, ok=false if it did not work.
    niks3_token (default True) gives the worker its own short-lived niks3
    push token, valid as long as the worker (extend() renews it), which the
    `niks3` command on the worker uses (`niks3 push PATH`); the result has a
    niks3_token object, ok=false if it did not work. Pass False to keep it
    off the worker. The browser-daemon profile never gets one.
    Returns name, ip, host_key, user and expires_at. Always call down() when
    the task is done.
    """
    argv = ["up", "--json", "--ttl", ttl]
    if flavor:
        argv += ["--flavor", flavor]
    if profile:
        argv += ["--profile", profile]
    if disk_gib:
        argv += ["--disk", str(disk_gib)]
    if scratch:
        argv.append("--scratch")
    if topic:
        argv += ["--topic", topic]
    if not nix_cache:
        argv.append("--no-nix-cache")
    if not niks3_token:
        argv.append("--no-niks3-token")
    return json.loads(run(*argv, timeout=1200))


@mcp.tool()
def profiles() -> list:
    """List worker profiles with their effective flavor, disk and image tags."""
    return json.loads(run("profiles", "--json", timeout=120))


@mcp.tool()
def ls() -> list:
    """List all workers: ad-hoc ones (kind adhoc) and nixbot's pool (pool)."""
    return json.loads(run("ls", "--json", timeout=120))


@mcp.tool()
def inspect(name: str, boot: bool = False) -> dict:
    """Everything known about one worker: owner, creator (agent, PID,
    session, topic, cwd), expiry, grace period, max lifetime and server
    metadata. boot=True adds the worker's own /run/rworker/metadata.json."""
    argv = ["inspect", name, "--json"]
    if boot:
        argv.append("--boot")
    return json.loads(run(*argv, timeout=120))


@mcp.tool()
def extend(name: str, ttl: str, niks3_token: bool = True) -> dict:
    """Move a worker's expiry to now + ttl (capped at its maximum lifetime).
    A worker that has a niks3 push token gets a new one for the new expiry
    (the result's niks3_token object); niks3_token=False skips that."""
    argv = ["extend", name, "--ttl", ttl, "--json"]
    if not niks3_token:
        argv.append("--no-niks3-token")
    return json.loads(run(*argv, timeout=120))


@mcp.tool()
def niks3_token(name: str) -> dict:
    """(Re)issue a worker's short-lived niks3 push token for the rest of its
    lifetime: for a worker created with niks3_token=False, or to retry a
    failed install. The `niks3` command on the worker then pushes to the
    cache (`niks3 push PATH`, pins limited to rworker-*)."""
    return json.loads(run("niks3-token", name, "--json", timeout=180))


@mcp.tool()
def down(name: str) -> dict:
    """Delete a worker (server, volume, NetBird peer). Nothing survives."""
    return json.loads(run("down", name, "--json", timeout=300))


@mcp.tool()
def prune(names: list[str] | None = None, all: bool = False,
          dry_run: bool = False) -> list:
    """Delete several ad-hoc workers: the named ones, or else all of this
    user's; all=True deletes every ad-hoc worker, whoever owns it. Pool
    workers are never pruned. dry_run=True only lists them."""
    argv = ["prune", "--json", *(names or [])]
    if all:
        argv.append("--all")
    argv.append("--dry-run" if dry_run else "--yes")
    return json.loads(run(*argv, timeout=900))


@mcp.tool()
def exec(name: str, command: str, workdir: str | None = None,
         timeout_seconds: int = 600) -> dict:
    """Run a registered job and wait. On timeout the job continues; use logs()."""
    job = start(name, command, workdir=workdir)
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        listing = run("jobs", name, timeout=60)
        for row in listing.splitlines():
            fields = row.split("\t")
            if len(fields) >= 2 and fields[0] == job and fields[1].startswith("exit "):
                output, truncated = tail(run("logs", name, job, "--lines", "200", timeout=60))
                return {"job": job, "exit_code": int(fields[1][5:]),
                        "stdout": output, "stderr": "", "truncated": truncated}
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    return {"job": job, "exit_code": None,
            "error": "timed out; job continues, use logs()"}


@mcp.tool()
def start(name: str, command: str, session: str | None = None,
          workdir: str | None = None) -> str:
    """Start a registered job. Returns its ID for jobs() and logs().

    session optionally names the job; omit it to generate a unique ID.
    """
    argv = ["start", name]
    if session:
        argv += ["--name", session]
    if workdir:
        argv += ["--workdir", workdir]
    return run(*argv, "--", command, timeout=60).strip()


@mcp.tool()
def jobs(name: str) -> str:
    """List registered jobs, their status, and start time."""
    return run("jobs", name, timeout=60)


@mcp.tool()
def logs(name: str, session: str | None = None, lines: int = 200) -> str:
    """Show recent logs for all jobs, or for the named job."""
    argv = ["logs", name]
    if session:
        argv.append(session)
    return tail(run(*argv, "--lines", str(lines), timeout=60))[0]


@mcp.tool()
def register(name: str, job: str, log_path: str) -> str:
    """Register an existing absolute log-file path on a worker."""
    run("register", name, job, "--log", log_path, timeout=60)
    return job


@mcp.tool()
def sync(name: str, src: str, dest: str | None = None) -> dict:
    """rsync a local directory to the worker (mirrors with --delete; skips
    target/, .direnv/ and result). dest defaults to the directory's name in
    the agent's home."""
    argv = ["sync", "--json", name, src] + ([dest] if dest else [])
    return json.loads(run(*argv, timeout=1800))


@mcp.tool()
def nix_cache(name: str, dry_run: bool = False) -> dict:
    """Let a worker substitute from the private S3 Nix cache, using this
    host's own settings: its s3:// substituters, the trusted public keys and
    the one AWS profile they name (read-only), pushed over SSH into
    /run/rworker-nix on the worker. Nothing else of nix.conf is copied. Run
    it again after the key was rotated. dry_run shows what would be pushed
    (never credentials). ok=false: see daemon (image-too-old, timeout) and
    reachable."""
    argv = ["nix-cache", name, "--json"] + (["--dry-run"] if dry_run else [])
    return json.loads(run(*argv, timeout=300))


@mcp.tool()
def builder(name: str) -> str:
    """A Nix --builders line for the worker: nix build --max-jobs 0
    --builders "<line>" .#pkg builds there and copies the result back."""
    return json.loads(run("builder", name, "--json", timeout=60))["builder"]


if __name__ == "__main__":
    mcp.run()
