---
name: nix
description: Use when editing, evaluating, building or deploying NixOS or Home Manager configuration (hosts, modules, profiles, services, packages, flake inputs), when a build or evaluation must run on a remote build host. Directs agents to the nixos-config repositories and their AGENTS.md guidelines, and ships the remote-sync helper script.
---

# Nix

Use this skill for NixOS and Home Manager configuration tasks.

Before making changes or running deployments, read `AGENTS.md` in the root of the relevant repository for environment setup, deployment workflows, code style, repository layout, and conventions.

When repository guidance sends evaluations or builds to a remote host, keep its
`~/build` directory tidy. Remove only stale files from your own earlier runs,
never another agent's files or anything with unclear ownership. Prefer an
agent- or run-specific directory when the remote is shared, and do not sync
with deletion into a shared directory. Periodically remove your own obsolete
build directories once no job is using them.

## Coordinating deployments

Before deploying to a host (`just deploy <host>`, or restarting
`nixos-upgrade.service` on it), check Concord for other agents deploying to the
same target: `inspect_work`, then `start_work` with `modules: ["deploy:<host>"]`.
If someone holds that module, wait for their `finish_work` or prompt them with
`update_work`; do not deploy over them. Release the claim with `finish_work` as
soon as the switch is verified. See "Deployment" in `AGENTS.md` for the full rule.

## Remote evaluation and CI helpers

Before copying a remotely updated `flake.lock` back, compare the local lock
against the version originally synced. If another agent changed it meanwhile,
resync the current lock and repeat the input update remotely. Review the final
diff to ensure unrelated inputs were preserved before committing.

Never evaluate or build on the machine the agent runs on (see `AGENTS.md`). Prefer an ad-hoc
`rworker` (see the `rworker` skill: `rworker exec --sync SRC -- CMD`, or `sync` + `ssh`), which
needs no `~/build` cleanup; the scripts below target the shared build nodes. Two scripts in this
skill's `scripts/` directory replace the hand-typed rsync/ssh and `gh run` loops:

- `scripts/remote-sync.sh [--host rofl-14] [--name NAME] [--private DIR] SRC [-- COMMAND]` rsyncs
  SRC to `~/build/NAME` on rofl-13 without `.git` (removing a stale remote one), optionally syncs
  the private checkout too, and runs COMMAND there. `@PRIVATE@` in COMMAND becomes the remote
  private path:

  ```
  remote-sync.sh --private ~/devel/private/pschmitt/nixos-config-private.git \
    ~/devel/private/pschmitt/nixos-config.git \
    -- "nix eval --override-input nixos-config-private path:@PRIVATE@ '.#nixosConfigurations.rofl-10.config.system.build.toplevel.drvPath'"
  ```

  Other projects (cargo builds, flakes of rbw or browser-daemon) use the same script with their
  own `--name`. Clean up your own `~/build/<name>` directories afterwards.
- After pushing, load the `ci-watch` skill to wait for CI without polling.

## Repositories

### nixos-config (Public)

Main NixOS and Home Manager system configuration repository.

- **Local path**:
  - `~/devel/private/pschmitt/nixos-config.git`
- **Git URLs**:
  - `git@github.com:pschmitt/nixos-config.git`
  - `https://github.com/pschmitt/nixos-config.git`
- **Guidelines**: Read `AGENTS.md` in the repository root.

### nixos-config-private (Private)

Private counterpart repository containing SOPS secrets, private host configurations, OpenTofu infrastructure, and private services.

- **Local path**:
  - `~/devel/private/pschmitt/nixos-config-private.git`
- **Git URLs**:
  - `git@github.com:pschmitt/nixos-config-private.git`
  - `https://github.com/pschmitt/nixos-config-private.git`
- **Guidelines**: Read `AGENTS.md` in the repository root.
