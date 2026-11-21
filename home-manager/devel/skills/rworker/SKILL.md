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

Workers are reached over NetBird or Tailscale (both joined; the client uses whichever answers). You log in as
`agent` with your own SSH key (handed over at creation); the worker's host
key is pinned on creation, never trusted on first use.

## Commands

A worker NAME may be abbreviated to a unique prefix or substring (`rworker logs -f 3e19`);
an ambiguous one lists the candidates. The shell completions (`rk`) complete names, also after flags.

All through `rworker` (on PATH via Home Manager; the package is
`github:pschmitt/rworker`, configured by `programs.rworker`). It calls `rworker` on the control host (rofl-10)
over SSH and keeps per-worker state in `~/.local/state/rworker`:

```bash
w=$(rworker up --ttl 3h --topic "rbw release build" --json | jq -r .name)  # ~1-4 min
rworker sync "$w" ~/devel/private/pschmitt/rbw.git rbw
rworker ssh "$w" 'cd rbw && nix develop -c cargo build --release'
rworker down "$w"
```

`RWORKER_KEY` must name the **public** SSH key file (`.pub`), never the private key: `up` sends its contents to the worker-control command. `builder` strips `.pub` to find the private key; `ssh` and `sync` need it in the SSH agent or configuration.

- `up [--ttl 90m|2h] [--flavor s1.2xlarge] [--disk 250]` prints a summary;
  `--profile browser-daemon` is the image for browser-daemon's ephemeral
  browser nodes (small `s1.medium.d`), not for building anything, browser-daemon
  included: builds and tests use the default `standard` profile (the
  build-worker image, `s1.xlarge`). `exec` and `ssh --create` accept it too.
  `--profile large-builder` uses the build image with `s1.2xlarge` and a
  500 GiB disk; `--flavor` and `--disk` can override either default.
  with `-j`/`--json` (any action but `ssh` takes it) the JSON (`name`, `ip`,
  `host_key`, `expires_at`, `flavor`). Use `--json` in scripts; `--ssh`
  logs you in right away (interactive use); `ssh --create [up options]` is
  the same. **Always** pass `--topic "what it is for"` and `--agent-id ID`
  (your Concord agent id, e.g. `claude-code:ca5ed9b8`; also read from
  `RWORKER_AGENT_ID` / `CONCORD_AGENT_ID`) with `up`, `exec` and
  `ssh --create` (MCP `up(topic=..., agent_id=...)`): without them `ls` shows
  `-` and nobody can tell whose worker it is or whether it is safe to delete.
  **When you reuse a worker** (one you did not create, or one made for earlier
  work), take it over first: `claim NAME --topic "new topic" --agent-id ID`
  (MCP `claim(name, topic, agent_id)`). It replaces the creator info (agent,
  agent id, PID, session, cwd) and the topic in one go, so `ls` and the
  filters stay truthful; `topic NAME "text"` changes only the topic (ad-hoc
  only, empty clears it). Agent, PID, session and cwd are recorded on their
  own at creation and by `claim`. Ask for a bigger flavor only for
  genuinely parallel builds; it fails fast when the quota is used up.
- `profiles [--json]` lists the profiles (flavor, disk, image tags); select
  one with `up --profile NAME`.
- `prune [NAME...] [--all] [--yes] [--dry-run]` deletes several ad-hoc
  workers: the named ones, else all of yours; `--all` every ad-hoc worker.
  It asks first; pass `--yes` in scripts. Pool workers are never pruned.
- `ls` lists all workers (ad-hoc and nixbot's pool, `KIND` tells them
  apart) with owner, creating agent, topic and expiry (`-o wide` adds the
  agent id, flavor, IP and cwd). `ls`, `logs` and `events` filter with the
  regexes `--agent` (claude, codex, ...), `--agent-id` (a Concord id) and
  `--topic`; a leading `!` inverts one, e.g. `ls --agent-id claude-code:ca5ed9b8`
  shows your own workers (MCP `ls(agent_id=...)`); `inspect NAME [--boot]` shows
  everything about one worker; `ls --watch` redraws it in place and marks
  new (`+`), changed (`~`) and gone (`-`) workers; `extend NAME --ttl 2h`
  moves the expiry; `down NAME` deletes the worker and its overlay peers
  (a pool worker only with `--force`: its builds fail, the autoscaler replaces it).
- On the worker, `rworker-metadata [--json]` shows what it is: name,
  owner, creator, current expiry and lifetime, CPUs, memory, disk.
- `ssh NAME [CMD]` and `sync NAME SRC [DEST]` use the pinned host key.
  `sync` mirrors with `--delete` and skips `target/`, `.direnv/`, `/result`.
- `cp NAME:REMOTE LOCAL` / `cp LOCAL NAME:REMOTE` copies files or
  directories (rsync, like scp). `cp NAME:repo/src/ ./` copies the *contents*
  of `src`, `cp NAME:repo/src ./` the dir. In zsh write `"${w}:path"`, never
  `"$w:path"`: `:t`/`:h`/`:r` are modifiers, `cp` then only prints its usage.
  `exec [up options] [--sync SRC[:DEST]]
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
- `setup nix NAME [--no-cache] [--no-auth] [--auth-host HOST]... [--dry-run]`
  (MCP `setup_nix`) gets the worker ready to use your host's Nix, in two
  parts, both on by default: **cache**, so it substitutes from the private
  S3 Nix cache (your host's `s3://` substituters, the trusted public keys and
  the one AWS profile those URLs name), and **auth**, your host's Nix
  `access-tokens` (for example github.com and git.wiit.one), so it fetches
  private flake inputs itself instead of receiving them from you. `up` and
  `exec` do both by default as far as your host has something to give
  (`--no-nix-cache` / `--no-nix-auth`, MCP `up(nix_cache=false,
  nix_auth=false)` skip one). Everything goes over SSH into `/run/rworker-nix`
  (tmpfs, agent-owned, 0700); nothing else of `nix.conf` is copied. The
  worker's nix-daemon restarts on its own. It puts credentials on the worker,
  which anyone with a shell there can read; the worker is private and
  temporary, so the host's own profile is acceptable. Re-run it after a key
  or token is rotated. `nix-cache NAME` (MCP `nix_cache`) is the cache part
  alone. Workers created before the feature get nothing and the command says
  so. `setup` is where more preparation (gradle, ssh, ...) will go.
- Every worker gets its own short-lived niks3 push token (`niks3 push` on the
  worker, with the closure on `--stdin`; `--no-niks3-token` or MCP `up(niks3_token=false)` opts out,
  `niks3-token NAME` reissues): see [host-closures](references/host-closures.md).

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
- **Android/Gradle:** `nix develop` needs the project's Android SDK shell; give
  it `--disk 250` (Gradle caches are large) and a TTL covering the first build.
  Pass `-Pandroid.aapt2FromMavenOverride="$ANDROID_HOME/build-tools/<ver>/aapt2"`
  to `./gradlew` so AGP uses the Nix-wrapped `aapt2` instead of Maven's binary.
- **Nix evaluation:** Remote builders and `--eval-store` do not move evaluation.
  Sync the tree and run Nix on the worker for expensive evaluations. Follow
  the repository's workload policy for deciding when to offload.
- **Nix builds:** `nix build --max-jobs 0 --builders "$(rworker builder "$w")"
  .#pkg` builds on the worker and copies the result back. The worker
  substitutes from cache.nixos.org and nixbot's store itself, and from the
  private S3 cache unless it was created with `--no-nix-cache`. Add
  `--option builders-use-substitutes true` so inputs are fetched on the
  worker instead of being copied up from here.
- **Checking a flake on a worker:** sync the checkout to a run-specific worker
  directory. `rworker sync` copies `.git`; remove only that directory's `.git`
  before running Nix so it sees the synced working tree, including uncommitted
  changes. For private inputs, see **Secrets and private inputs**. Pass
  `--accept-flake-config` when the project requires its configured substituters
  or other trusted settings. If updating inputs there, review the resulting
  lockfile against the pre-update copy; run the repository's checks and build
  its required outputs on the worker. Copy back only the reviewed files, and
  remove the auth file before deleting the worker.
- **Whole host closures and big transfers:** build them on a `--profile
  large-builder` worker and keep the result off the home link; see
  [host-closures](references/host-closures.md); aarch64 targets: [cross-arch](references/cross-arch.md).
- **Pushing to the S3 cache:** use the worker's own niks3 token and push the
  whole closure: `nix path-info -r PATH | niks3 push --stdin`. A bare
  `niks3 push PATH` uploads nothing when PATH itself is already cached, even
  if its references are not ([host-closures](references/host-closures.md)). Only for what niks3 cannot do may you put the S3 credentials of the
  agent's own host on a worker without asking: the AWS profile the host's
  `s3://` substituter names, as `nix-cache` transfers it or as a mode-0600
  file (see **Secrets and private inputs**), never the whole credentials file,
  never in arguments or the Nix store, and `down` the worker when done. If
  that profile cannot write, build on the target or ask before a large
  upload over the home link.
- Agents must run long jobs with `rworker start "$w" -- 'command'` or MCP
  `start`, and short jobs with MCP `exec` when available. These register the
  job and capture combined output. Use `rworker jobs "$w"`, `rworker logs
  `"$w" [JOB] [--lines N]` to inspect one worker, or `rworker logs [--lines N]`
  to inspect all workers. **Never filter a job's output inside the worker**
  (`... | tail -n 10`, `> /dev/null`, `2>&1 | rg ...`): the user follows the
  jobs live with `rworker logs -f`, and a trimmed job prints nothing until it
  ends. Let the command write everything to stdout/stderr (`nix build -L`
  for build logs) and trim on your side when reading, e.g.
  `rworker logs "$w" JOB --lines 40`. `rworker logs -f` follows all jobs across all workers
  (`--topic`/`--agent` regex-filter `logs`/`events`; a leading `!` inverts, e.g. `--topic '!build'`), with colored `WORKER/JOB` prefixes. It discovers new jobs within about one
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

Credentials the task needs (S3 cache credentials, a GitHub token for a private
flake input) may go to a worker without asking, as a file and never in the
transcript; delete them before `down`. Details, the private-flake `nix-auth.conf`
recipe and the checkout-at-pinned-revision alternative:
[secrets-private-inputs](references/secrets-private-inputs.md).

## Changing rworker

See [maintenance](references/maintenance.md) when changing the client.

## Rules

- **Before `down`, push what the worker built to the S3 cache.** After any
  Nix build on a worker (host closures, packages, expensive derivations, also
  a failed run that got part-way), push the closure with the worker's own niks3
  token: `nix path-info -r PATH | niks3 push --stdin` (see **Pushing to the S3
  cache**). Agents have deleted workers before pushing, and the expensive
  derivations had to be built again for no reason. Check the push succeeded
  (`nix path-info --store 's3://…' PATH`, or the `niks3` exit status) before
  you run `down`; if it cannot be pushed, copy the result back or ask first.
- Always `down` the worker when the task is done, even after a failure; do
  not leave it for the TTL. Extend instead of creating a second one.
- Nothing on a worker survives. Copy results off before `down`.
- Credentials the task needs may go to a worker (see **Secrets and private
  inputs**), as a file and never in the transcript. The automatic S3 cache
  key is handled separately by `rworker`.
- Parallel agents (subagents building at the same time) get one worker each:
  several cargo builds on one worker overload it until SSH and NetBird time out.
- Prefer a worker over the shared build nodes for anything that takes more
  than a few minutes of full CPU.
