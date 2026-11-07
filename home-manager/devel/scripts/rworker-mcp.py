"""MCP server for ad-hoc build workers (rworker).

A thin layer over the `rworker` client (skills/rworker), so host-key
pinning, local state and SSH keys work exactly as on the command line:
create a short-lived encrypted build VM, run commands or long jobs on it,
copy sources over, use it as a Nix builder, and delete it again.
"""

import argparse
import json
import shlex
import subprocess

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
def extend(name: str, ttl: str) -> dict:
    """Move a worker's expiry to now + ttl (capped at its maximum lifetime)."""
    return json.loads(run("extend", name, "--ttl", ttl, "--json", timeout=120))


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
    """Run a shell command on the worker as user agent and wait for it.

    Use start()/logs() instead for anything that may take longer than a few
    minutes. stdout/stderr are trimmed to their last 20000 characters.
    """
    script = command if not workdir else f"cd {shlex.quote(workdir)} && {command}"
    try:
        proc = subprocess.run(
            [args.rworker, "ssh", name, "bash", "-lc", shlex.quote(script)],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return {"exit_code": None, "error": f"timed out after {timeout_seconds}s; "
                "use start() for long jobs"}
    stdout, out_cut = tail(proc.stdout)
    stderr, err_cut = tail(proc.stderr)
    return {"exit_code": proc.returncode, "stdout": stdout, "stderr": stderr,
            "truncated": out_cut or err_cut}


@mcp.tool()
def start(name: str, command: str, session: str = "job",
          workdir: str | None = None) -> str:
    """Start a long-running command in a detached tmux session on the worker.

    The job survives dropped connections; read its output with logs(). A busy
    worker is not deleted when its TTL runs out.
    """
    script = command if not workdir else f"cd {shlex.quote(workdir)} && {command}"
    inner = f"{script}; echo; echo \"[exit $?]\"; exec bash"
    remote = f"tmux new-session -d -s {shlex.quote(session)} {shlex.quote(inner)}"
    subprocess.run([args.rworker, "ssh", name, remote], check=True,
                   capture_output=True, text=True, timeout=60)
    return f"started tmux session {session!r} on {name}; read it with logs()"


@mcp.tool()
def logs(name: str, session: str = "job", lines: int = 200) -> str:
    """Last lines of a tmux session started with start() ("[exit N]" at the end
    means the command finished with status N)."""
    remote = (f"tmux capture-pane -p -J -S -{int(lines)} "
              f"-t {shlex.quote(session)}")
    proc = subprocess.run([args.rworker, "ssh", name, remote],
                          capture_output=True, text=True, timeout=60)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "no such session")
    return tail(proc.stdout)[0]


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
