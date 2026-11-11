---
name: rworker
description: Create a short-lived, encrypted build VM (ad-hoc worker) on the WIIT OpenStack for heavy compiles - Rust, Android/Gradle, large Nix builds - instead of loading the local machine or the shared build nodes, and delete it afterwards. Use when a build or test is too heavy or too long for this host, or when the user asks for a worker, a build VM, "rworker" or "a rofl worker".
---

# rworker

Ad-hoc workers are disposable VMs (16 vCPU / 32 GiB / 150 GiB by default)
booted from the nixbot worker image. Everything except the boot partition
is encrypted with a key that exists only in the worker's RAM; a reboot or
`down` destroys the data. A worker expires on its own after its TTL
(default 2 h, at most 24 h), so a forgotten one does not run forever; one
still in use at expiry (SSH sessions, builds, load) is kept until it has
been idle for 1 h, never past its maximum lifetime. At
most 10 exist at a time, sharing a quota with nixbot's own build pool.

Workers are reached over NetBird from servers and laptops. You log in as
`agent` with your own SSH key (handed over at creation); the worker's host
key is pinned on creation, never trusted on first use.

## Commands

All through `rworker` (on PATH via Home Manager; the same code is
`scripts/rworker.sh`). It calls `rworker` on the control host (rofl-10)
over SSH and keeps per-worker state in `~/.local/state/rworker`:

```bash
w=$(rworker up --ttl 3h --topic "rbw release build" --json | jq -r .name)  # ~1-4 min
rworker sync "$w" ~/devel/private/pschmitt/rbw.git rbw
rworker ssh "$w" 'cd rbw && nix develop -c cargo build --release'
rworker down "$w"
```

- `up [--ttl 90m|2h] [--flavor s1.2xlarge] [--disk 250]` prints a summary;
  `--profile browser-daemon` selects the browser-ready image; the default `standard`
  profile stays the build-worker image. `exec` and `ssh --create` accept it too.
  `--profile large-builder` uses the build image with `s1.2xlarge` and a
  500 GiB disk; `--flavor` and `--disk` can override either default.
  with `-j`/`--json` (any action but `ssh` takes it) the JSON (`name`, `ip`,
  `host_key`, `expires_at`, `flavor`). Use `--json` in scripts; `--ssh`
  logs you in right away (interactive use); `ssh --create [up options]` is
  the same. **Always** pass `--topic "what it is for"` (also with `exec` and
  `ssh --create`; MCP `up(topic=...)`): without it `ls` shows `-` and nobody
  can tell whose worker it is or whether it is safe to delete;
  the agent (claude, codex, agy, opencode, ...), its PID, session
  and the cwd are recorded on their own. Ask for a bigger flavor only for
  genuinely parallel builds; it fails fast when the quota is used up.
- `profiles [--json]` lists the configured profiles with effective flavor,
  disk size and image tags; use `up --profile NAME` to select one.
- `prune [NAME...] [--all] [--yes] [--dry-run]` deletes several ad-hoc
  workers: the named ones, else all of yours; `--all` every ad-hoc worker.
  It asks first; pass `--yes` in scripts. Pool workers are never pruned.
- `ls` lists all workers (ad-hoc and nixbot's pool, `KIND` tells them
  apart) with owner, creating agent, topic and expiry (`-o wide` adds the
  agent's PID, flavor, IP and cwd); `inspect NAME [--boot]` shows
  everything about one worker; `ls --watch` redraws it in place and marks
  new (`+`), changed (`~`) and gone (`-`) workers; `extend NAME --ttl 2h`
  moves the expiry; `down NAME` deletes the worker and its NetBird peer
  (a pool worker only with `--force`: builds running on it fail
  and the autoscaler replaces it from the current image).
- On the worker, `rworker-metadata [--json]` shows what it is: name,
  owner, creator, current expiry and lifetime, CPUs, memory, disk.
- `ssh NAME [CMD]` and `sync NAME SRC [DEST]` use the pinned host key.
  `sync` mirrors with `--delete` and skips `target/`, `.direnv/`, `result`.
- `cp NAME:REMOTE LOCAL` / `cp LOCAL NAME:REMOTE` copies files or
  directories (rsync, like scp). Mind rsync's trailing slash:
  `cp NAME:repo/src/ ./` drops the *contents* of `src` into `./`; to bring a
  directory back to the same place use `cp NAME:repo/src/ ./src/` (or omit
  the slash: `cp NAME:repo/src ./`). `exec [up options] [--sync SRC[:DEST]]
  [--fetch REMOTE[:LOCAL]] -- CMD` is a one-shot worker: create, copy, run,
  fetch, delete (also on failure; `--keep-on-failure` to debug).
  The command runs from `/home/agent`, and `--sync SRC:DEST` puts the
  *contents* of SRC in `~/DEST`. `exec` and `ssh` join their arguments with
  spaces before the remote shell parses them, so
  `-- bash -lc 'cd x && make'` runs `bash -lc cd` and then `make` in the home
  directory, with no error. Pass the whole command as one string:
  `-- 'cd x && make'` (or `-- "$CMD"`), and quote nested shells inside it.
  Print each step's result (`; echo STEP_DONE`) and keep stderr: with
  `set -e` and `>/dev/null`, a failure leaves no output at all.
- `builder NAME` prints a Nix `--builders` line for the worker.
- `nix-cache NAME [--dry-run]` (MCP `nix_cache`) lets the worker substitute
  from the private S3 Nix cache. `up` and `exec` do it by default when your
  host's Nix has an `s3://` substituter; `--no-nix-cache` (MCP
  `up(nix_cache=false)`) skips it. Your host pushes its
  `s3://` substituters, the trusted public keys and the one AWS profile
  those URLs name over SSH into `/run/rworker-nix` (tmpfs, agent-owned,
  0700); nothing else of `nix.conf` is copied. The worker's nix-daemon
  restarts on its own. It puts a credential on the worker, which anyone with
  a shell there can read; the worker is private and temporary, so the host's
  own profile is acceptable. Re-run it
  after the key is rotated.
  Workers created before the feature get nothing and the command says so.

MCP: the `rworker` MCP server offers the same as tools (`profiles` lists the
available configurations; `up` accepts `profile`
and has `nix_cache` on by default), `ls`, `extend`, `down`, `prune`, `exec`, `start`/`jobs`/`logs` for
registered jobs, `register` for existing log files, `sync`, `nix_cache`, `builder`). Prefer it when it is
loaded; the CLI is the fallback. A running MCP server only gains new tools
after its client restarts.

## Patterns

- **Rust:** `sync` the tree, then `ssh "$w" 'cd X && nix develop -c cargo
  build'`. Fetch artifacts back with `rsync` and the same `ssh` options, or
  build through Nix (below) so results land in the local store. If restoring a
  worker-only test mutation with `sync`, touch the restored source on the
  worker before retesting: rsync preserves its older timestamp, so Cargo can
  otherwise reuse the mutated test binary. When the synced tree has no `.git`,
  Nix treats it as a path flake and snapshots the whole source on every
  `nix develop`, including a `target/` created by an earlier Cargo run. This
  can copy gigabytes and race a running build. Keep Cargo output outside the
  flake from the first run, for example:

  ```bash
  rworker start "$w" -- 'cd rbw && CARGO_TARGET_DIR="$HOME/build-target/rbw" nix develop -c cargo test'
  ```

  If `target/` already exists, move it to that target directory first, then use
  the same `CARGO_TARGET_DIR` for subsequent commands. Refresh the source as
  usual when flake inputs or source files change.
- **Android/Gradle:** `nix develop` needs the project's Android SDK shell;
  give it `--disk 250` (Gradle caches are large) and a TTL that covers the
  first, uncached build.
- **Nix builds:** `nix build --max-jobs 0 --builders "$(rworker builder "$w")"
  .#pkg` builds on the worker and copies the result back. The worker
  substitutes from cache.nixos.org and nixbot's store itself, and from the
  private S3 cache unless it was created with `--no-nix-cache`. Add
  `--option builders-use-substitutes true` so inputs are fetched on the
  worker instead of being copied up from here.
- **Keep big closures off the home link.** The user's home connection is DSL
  and slow: copying a large result back to the agent's host wastes their
  bandwidth and time. Fetch only small artifacts home. For a closure that
  other hosts will deploy, have it go from the worker to the S3 cache and let
  the targets substitute, or build on the target itself.
- **Pushing to the S3 cache is fine, with the local credentials.** Workers
  are private and temporary, so the user allows using the S3 credentials of
  the agent's own host on a worker, without asking each time: the same AWS
  profile the host's `s3://` substituter names, as `nix-cache` already
  transfers it, or as a mode-0600 file (see **Secrets and private inputs**).
  Never copy the whole credentials file, never put the key in arguments or
  the Nix store, and `down` the worker when done. Use the host's existing
  cache signing key the same way. This covers the cache only: it does not
  loosen the rules for other credentials. If the local profile cannot write
  to the bucket, copy the closure back and push from the agent's host, or
  build on the target; ask before a large upload over the home link.
- Agents must run long jobs with `rworker start "$w" -- 'command'` or MCP
  `start`, and short jobs with MCP `exec` when available. These register the
  job and capture combined output. Use `rworker jobs "$w"`, `rworker logs
  `"$w" [JOB] [--lines N]` to inspect one worker, or `rworker logs [--lines N]`
  to inspect all workers. `rworker logs -f` follows all jobs across all workers,
  with colored `WORKER/JOB` prefixes. It discovers new jobs within about one
  second and rescans the worker list every five seconds, attaching to new workers
  and stopping when workers disappear. `rworker events` emits only lifecycle
  changes after its initial snapshot: workers added or deleted, jobs added or
  deleted, and job state changes. Use `rworker events --interval N` to set the
  polling interval in seconds. Each unnamed job gets a unique ID. MCP `exec`
  returns the ID even on timeout;
  the job continues. If a job must be launched separately, register its existing
  absolute log file with `rworker register "$w" JOB --log /path/to/log` (or MCP
  `register`) immediately. Logs and metadata disappear with the worker.

## Secrets and private inputs

Credentials the task needs may be sent to a worker. Workers are private and
temporary, and the user allows it without asking each time: this holds for
the S3 cache credentials, a GitHub token for a private flake input and
whatever else the build or test needs. For a private flake input you can also
transfer a checkout at the exact revision pinned in `flake.lock` and use
`--override-input NAME path:<worker-checkout>`. Verify the revision first; a
dirty checkout changes what is evaluated. Remember that Nix may copy the
source into the worker's world-readable store: never include plaintext
secrets. `rworker sync` does **not** exclude `.git` by itself.

Sending a credential does not make it safe to show. The worker user and
administrators can read it, and processes or tools may copy or log it, so keep
it out of the transcript: pass it as a file, never in MCP arguments,
command-line arguments, Git, Nix expressions or the Nix store, avoid shell
tracing and commands that print it, and delete it before `down`. A narrow,
short-lived credential is nicer when it is cheap to get, but it is not
required. Prefer sending just the file or entry the job needs over a whole
credentials directory or the SSH agent.

The worker may remove an agent user's `/dev/shm` files when its last SSH login
ends. If the next command needs the file, keep one SSH session open through
the transfer and consumption, or send it on stdin to the consuming command in
the same SSH session. For a locally prepared mode-0600 `secret_file`:

```bash
rworker ssh "$w" 'umask 077; d=$(mktemp -d /dev/shm/rworker-secret.XXXXXXXX); trap '\''rm -rf "$d"'\'' EXIT; cat > "$d/credential"; your-command "$d/credential"' < "$secret_file"
```

Check each step; if transfer or the job fails, still remove the directory and
tear down the worker. Remove any local temporary secret file, revoke temporary tokens
when finished, and always `down` the worker. Do not assume deletion erases
copies made by the workload.

For a GitHub private flake fetch, the file may instead be a minimal Nix user
configuration containing only the scoped `access-tokens` entry, prepared locally
without printing the token. Run the worker's Nix command with
`NIX_USER_CONF_FILES=<worker-file-path>` in its environment; this replaces the
usual user configuration for that command. This authenticates the Nix client
fetch, not arbitrary build sandboxes or daemon-side private cache access. Do
not put the token itself in `NIX_CONFIG` or a command argument. The separate
`nix-cache` mechanism above handles its own read-only S3 credentials.

## Changing rworker

See [maintenance](references/maintenance.md) when changing the client.

## Rules

- Always `down` the worker when the task is done, even after a failure; do
  not leave it for the TTL. Extend instead of creating a second one.
- Nothing on a worker survives. Copy results off before `down`.
- Credentials the task needs may go to a worker (see **Secrets and private
  inputs**), as a file and never in the transcript. The automatic S3 cache
  key is handled separately by `rworker`.
- Prefer a worker over the shared build nodes for anything that takes more
  than a few minutes of full CPU.
