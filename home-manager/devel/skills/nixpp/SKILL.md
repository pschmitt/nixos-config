---
name: nixpp
description: Use when upgrading, inspecting, rolling back or debugging the Nix guest system on a TermuxPP phone with `nixpp` (status, generations, upgrade, rebuild, doctor, gc, recover), when deploying a nixos-config or termuxpp change to the phones, or when a phone's guest system is stale or broken after an upgrade.
---

# nixpp

`nixpp` manages the declarative Nix guest system of a TermuxPP phone. The guest
system is `termuxppConfigurations.<host>.system` in nixos-config; its source
and the `nixpp` code live in the termuxpp repository (`pkgs/nixpp`), consumed by
nixos-config through its `termuxpp` flake input. Background and the full command
reference: nixos-config `docs/termuxpp/system.md` and `docs/termuxpp/README.md`.
App builds and the fork itself are the `termuxpp` skill.

## Reach the guest

- Every change on a phone needs the exclusive Concord claim `android:<device>`
  in the nixos-config workspace first (`adb` skill, private `brkn-infra`
  android reference). Read-only `nixpp status` may run without it.
- Use the guest's SSH server: the phones have SSH aliases (see the private
  `brkn-infra` android reference). Run non-interactive commands with
  `ssh -o BatchMode=yes HOST 'nixpp status'`.
- Without SSH (another network, sshd gated by Wi-Fi), use
  `tpp-adb-shell --serial SERIAL -- COMMAND` over ADB. Connect a Wi-Fi ADB
  device first with `zsh -lc 'zhj adb::connect HOST'`.

## Inspect

```sh
nixpp status            # active and previous generation (JSON with --json)
nixpp generations       # all retained generations
nixpp doctor            # native controller, store, builders, signed cache pin
nixpp diff              # closure diff previous -> current
cat /etc/nixpp/upgrade.json   # flake, host and cache the upgrade uses
```

## Deploy a change to the phones

1. Push the change: to termuxpp `main` for nixpp or helper code, to
   nixos-config for the guest configuration.
2. For termuxpp changes, bump the input in nixos-config
   (`nix flake lock --update-input termuxpp`), check that only that input moved,
   commit `flake.lock` by path and push (`deploy` skill, steps 1-4).
3. Upgrade each phone, both in parallel:
   - **Published system (default):** `nixpp upgrade`. It installs the system
     that nixos-config CI built and pinned for the host in the signed cache;
     no evaluation or build on the phone. Only works once CI has published
     the pushed commit; `nixpp upgrade --dry-run` shows whether it has.
   - **Uncached ARM Rust builds:** If the guest closure needs to compile an
     `aarch64-linux` Rust package, including a newly pinned dependency such as
     `rworker`, use the `circus-build` skill to find or queue the exact
     revision's guest system build on a native ARM64 worker. Verify the
     assigned builder, then upgrade from the signed cache. An x86 builder can
     advertise `aarch64-linux` through emulation, and Rust builds there have
     repeatedly added tens of minutes to phone deployments.
   - **Without waiting for CI:** `nixpp upgrade --remote-eval` evaluates and
     builds the configured flake on the first reachable configured builder and
     switches; `nixpp upgrade --rworker --remote-eval` does the same on a
     disposable rworker. Use this path for cached closures or quick builds.
     Both imply `--build`, and neither flag guarantees a native ARM builder.
     Nix caches what
     `github:…/main` resolves to for about an hour; pass
     `--flake github:pschmitt/nixos-config/<sha>` for an exact commit.
   - **Built elsewhere (an rworker, by hand):** push the closure with
     `niks3 push` (worker tokens cannot move the `gh-main-*` pins), then on the
     phone copy it with `nix --refresh copy --from <cache store>`, using the
     store, credentials and keys from `/etc/nixpp/upgrade.json`, and run
     `nixpp prepare PATH` and `nixpp switch NAME`. Without `--refresh` a
     cached "not in cache" answer makes Nix report that no substituter can
     build the path.
   - Never build on the phone or the workstation: no plain `--build` without
     `--rworker` unless remote builders are configured (`--max-jobs 0`).
   - **"Existing file ... would be clobbered":** Home Manager found an
     unmanaged file where it wants a link. Run `nixpp recover` (the failed
     activation leaves a journal and blocks the next switch), then repeat the
     command with `--backup` (or `--backup=EXT`): the file moves to
     `<file>.nixpp.bak`, nothing is deleted. Works on `upgrade`, `fetch latest`,
     `rebuild` and `switch`. Do not move files by hand.
4. Verify with `nixpp status`: a new current generation with today's date.
   Release the device claim afterwards.

The nightly job (`termuxpp-nightly-update`) already runs the published-system
upgrade on Wi-Fi while charging; `termuxpp-nightly-update --check` shows its
readiness without activating anything.

## Recover

- `nixpp rollback` activates the retained previous generation.
- `nixpp recover` restores the generation recorded before an interrupted
  activation.
  A failed activation (for example Home Manager refusing to clobber an
  existing file) needs it before the next switch; then retry with `--backup`.
  If the error says `<file>.EXT` "would be clobbered by backing up", that
  backup already exists: move it away or use another `--backup=EXT`.
  `system.homeManagerBackupExtension` (default `nixpp.bak`; another extension
  or `null` to turn it off in `hosts/<host>/system.nix`) makes every
  activation, nightly included, do this; `--no-backup` overrides it.
- From an Android failsafe session, `nixpp native-shell` opens the native
  TermuxPP shell; the native controller runs independently of the guest.
- `nixpp gc --keep-generations N` prunes old generations; keep at least the
  previous one until a new generation is verified.
