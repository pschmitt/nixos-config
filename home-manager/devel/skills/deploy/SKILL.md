---
name: deploy
description: Use when asked to "deploy" something to the hosts - a project of ours (rbw, browser-daemon, bruvtab, monarch, teams-live, stricknani, ...) or a nixos-config / nixos-config-private change. Deploying means bumping the flake input in nixos-config, pushing and restarting nixos-upgrade on the relevant hosts. It does not mean cutting a version, tagging or publishing (that is the `release` skill).
---

# Deploy

"Deploy X" means: get the current state of X onto the hosts that use it. In practice:

1. bump X's input in the `nixos-config` flake lock,
2. commit and push,
3. restart `nixos-upgrade.service` on the relevant hosts,
4. verify the switch.

It does **not** mean tagging, versioning or publishing X. If the user wants a new version cut,
use the `release` skill and continue here afterwards. When "deploy" is ambiguous, this reading is
the default; do not start a release.

The user usually deploys **as soon as possible, to check on things live**. So be fast: no release,
no tag, no waiting for CI, no extra pre-flight checks beyond the ones below. Start with the host
the user will look at, and run the other hosts in parallel rather than one after another. Then
say where and what to look at (host, unit, version) as soon as it is live. Only slow down for a
real risk: a failed verification, an unexpected reboot, or someone else's live claim.

`AGENTS.md` of `nixos-config` has the rules (no local evaluation, Concord claims, deployment
gotchas). This skill is the order of steps.

## Steps

1. **Source is pushed.** Inputs such as `github:pschmitt/rbw` track the default branch, so the
   lock can only pick up pushed commits. Check `git status` and `git log @{u}..` in the project.
   No tag is needed for a deploy. Say so if the project has unpushed or uncommitted work you are
   not deploying.
2. **Bump the lock locally**: `nix flake lock --update-input <name>` in `nixos-config`. No
   `rworker` needed; a lock update puts no real load on the machine. (Builds and full
   evaluations still go to a worker.) For a change in
   `nixos-config-private`, push the private repo first, then bump `nixos-config-private`.
   browser-daemon has its own `rbw` input: after an rbw deploy, pin it to the same commit (rbw's
   `AGENTS.md`, "Deploy").
3. **Check the lock diff** before copying `flake.lock` back: only the intended input changed, and
   nobody edited the local lock meanwhile (`nix` skill). Pass `--override-input` for uncommitted
   private changes only when you really are testing, never for a deploy.
4. **Commit and push to `main`.** Message: `bump my privates` for the private input, otherwise a
   short description of what the bump brings ("Update teams-live push registration"). Leave
   unrelated modified files out. Signed commit: `gpg-signing` skill first.
5. **Pick the hosts.** Those that use the changed thing, by role (private `brkn-infra` skill).
   Skip images and throwaway hosts (`iso*`, `test-delete-*`). Decide from roles and what the
   input provides; do not evaluate to find out unless you are truly unsure, because it is slow
   (then compare `config.system.build.toplevel.drvPath` per host before and after the bump on the
   worker and deploy to the hosts whose derivation changed).
6. **Claim, then deploy, host by host.** Concord `start_work` with `modules: ["deploy:<host>"]`
   (look at `inspect_work` first). A claim whose holder is `agent-away` for hours is dead:
   check the host is idle (`systemctl is-active nixos-upgrade.service`, nothing mid-reboot), then
   clear it with `concord -C <repo> release <task> --close -r "<why>"` and go on. Then restart
   the unit:
   - on the current host: run locally, `sudo -n systemctl restart nixos-upgrade.service`
     (never SSH to yourself; without `sudo -n` it fails with "interactive authentication");
   - on another host: `ssh <host> sudo -n systemctl restart --no-block nixos-upgrade.service`
     (a non-root login needs `sudo -n` there too, and `--no-block` keeps the SSH call from
     waiting for the whole upgrade).

   Deploy from the pushed commit. To try something live before committing, use
   `just deploy <host>` from another host (`AGENTS.md`); commit and push once it works.
7. **Verify** each host: `readlink -f /run/current-system` changed, the unit is `inactive` with
   `Finished NixOS Upgrade` in `journalctl -u nixos-upgrade`, and the thing you deployed is there
   (version, unit, file). Read the end of the journal: if it says a reboot is needed, tell the
   user instead of rebooting. A `just deploy` SSH timeout is not a failure until you checked
   (`AGENTS.md`, deployment gotchas). Release the Concord claim as soon as the switch is verified.
8. **Report** what was bumped (old and new commit), which hosts, which were skipped or off.

## CI

Waiting for CI is optional at this stage. The deploy is the check: do not hold it back for the
`nixos-config` push, and load `ci-watch` only if the user asks or the change is large. (The
project's own CI is a `release` concern.)

## Traps

- `nixos-upgrade` deploys everything on `main`, not only your bump. A host far behind builds a lot
  and may pick up other agents' pending changes; look at `git log` since its generation if that
  matters.
- Do not run builds or full evaluations on the machine you are on. A lock update is fine.
- A host that serves builds to others must not restart mid-rollout: its upgrade can freeze the other
  hosts' upgrades in a copy. If they stall, restart their upgrades once it is back.
- A deploy that touches an agent skill or `CONTEXT.md` only takes effect in new sessions.
