---
name: rworker
description: Create a short-lived, encrypted build VM (ad-hoc worker) on the WIIT OpenStack for heavy compiles - Rust, Android/Gradle, large Nix builds - instead of loading the local machine or the shared build nodes, and delete it afterwards. Use when a build or test is too heavy or too long for this host, or when the user asks for a worker, a build VM, "rworker" or "a rofl worker".
---

# rworker

Ad-hoc workers are disposable VMs (16 vCPU / 32 GiB / 150 GiB by default)
booted from the nixbot worker image. Everything except the boot partition
is encrypted with a key that exists only in the worker's RAM; a reboot or
`down` destroys the data. A worker expires on its own after its TTL
(default 2 h, at most 24 h), so a forgotten one does not run forever. At
most 10 exist at a time, sharing a quota with nixbot's own build pool.

Workers are reached over NetBird from servers and laptops. You log in as
`agent` with your own SSH key (handed over at creation); the worker's host
key is pinned on creation, never trusted on first use.

## Commands

All through `rworker` (on PATH via Home Manager; the same code is
`scripts/rworker.sh`). It calls `rworker` on the control host (rofl-10)
over SSH and keeps per-worker state in `~/.local/state/rworker`:

```bash
w=$(rworker up --ttl 3h | jq -r .name)     # blocks ~2-4 min until ready
rworker sync "$w" ~/devel/private/pschmitt/rbw.git rbw
rworker ssh "$w" 'cd rbw && nix develop -c cargo build --release'
rworker down "$w"
```

- `up [--ttl 90m|2h] [--flavor s1.2xlarge] [--disk 250]` prints JSON
  (`name`, `ip`, `host_key`, `expires_at`). Ask for a bigger flavor only for
  genuinely parallel builds; it fails fast when the quota is used up.
- `ls` lists all ad-hoc workers with owner and expiry (`ls --all` adds
  nixbot's pool workers, `kind: pool`); `extend NAME --ttl 2h`
  moves the expiry; `down NAME` deletes the worker and its NetBird peer.
- `ssh NAME [CMD]` and `sync NAME SRC [DEST]` use the pinned host key.
  `sync` mirrors with `--delete` and skips `target/`, `.direnv/`, `result`.
- `builder NAME` prints a Nix `--builders` line for the worker.

MCP: the `rworker` MCP server offers the same as tools (`up`, `ls`,
`extend`, `down`, `exec`, `start`/`logs` for long jobs in tmux, `sync`,
`builder`). Prefer it when it is loaded; the CLI is the fallback.

## Patterns

- **Rust:** `sync` the tree, then `ssh "$w" 'cd X && nix develop -c cargo
  build'`. Fetch artifacts back with `rsync` and the same `ssh` options, or
  build through Nix (below) so results land in the local store.
- **Android/Gradle:** `nix develop` needs the project's Android SDK shell;
  give it `--disk 250` (Gradle caches are large) and a TTL that covers the
  first, uncached build.
- **Nix builds:** `nix build --max-jobs 0 --builders "$(rworker builder "$w")"
  .#pkg` builds on the worker and copies the result back. The worker
  substitutes from cache.nixos.org and nixbot's store itself.
- Long jobs: run them in `tmux` on the worker (`ssh "$w" tmux new -d -s b
  '...'`) so a dropped SSH session does not kill them; check back with
  `ssh "$w" tmux capture-pane -pt b`.

## Rules

- Always `down` the worker when the task is done, even after a failure; do
  not leave it for the TTL. Extend instead of creating a second one.
- Nothing on a worker survives. Copy results off before `down`.
- Workers carry no secrets. Do not copy credentials onto them; if a build
  needs a token, prefer running that step locally.
- Prefer a worker over the shared build nodes for anything that takes more
  than a few minutes of full CPU.
