---
name: termux-init
description: Install, recover, update, or verify the native Termux environment managed by yadm-init and nixpp on Android.
---

# Termux setup

Use this skill for first-run Termux setup, recovery after an interrupted
initializer, nixpp upgrades, and checks of the managed Termux generation and
yadm configuration.

Before changing a device, read the relevant sections of the
[`termux-native README`](https://github.com/pschmitt/nixos-config/blob/main/android/termux-native/README.md)
and [`nixpp README`](https://github.com/pschmitt/nixos-config/blob/main/android/nixpp/README.md).
They are the source of truth for the current bundle, bootstrap, and client
behavior.

## Select and inspect the phone

- Use the connected authorized transport available for the device: ADB or its
  configured SSH alias. For ADB, use the `adb` skill and select the device by
  serial; do not assume the first listed device is the intended phone.
- Confirm the Android device maps to one of the supported profiles: `p11`,
  `mp4`, or `zf10`.
- Inspect the existing Termux and generation state before modifying it. A
  successful shell prompt alone does not prove yadm bootstrap completed.
- Clearing Termux app data removes its private prefix, home, nixpp generations,
  and installer recovery files. Do this only when the user explicitly requests
  a clean reinstall. Check the backup before replacing or removing the prefix.

## First install or clean reinstall

Termux uses nixpp by default. Run the initializer in the visible Termux app
after the official app has completed first-run setup:

```sh
curl -fsSL https://yadm.brkn.lol | bash
```

Use `--legacy` only when the user explicitly requests the original non-nixpp
setup. Do not use `--archive-only` as a complete setup; it intentionally skips
yadm initialization. `--yes` skips the prefix replacement confirmation and is
appropriate only after the user has authorized replacing that prefix.

Keep Termux foregrounded while the initializer needs `/dev/tty`, and let the
whole command finish. If it reports that the environment was installed but
yadm setup did not finish, treat setup as incomplete. Inspect the exact error,
current prefix, and recovery backup first. Resume using the initializer's
supported `YADM_TERMUX_ARCHIVE_READY=1` and `YADM_INIT_NIXPP=1` recovery path;
do not reinstall the prefix just to retry yadm bootstrap.

For password-manager authentication, follow the `rbw` skill. Never print
secrets, put them in command arguments or shell history, or send them through
`adb input text`. Keep the bootstrap process short-lived and do not export
credentials into a long-lived shell. When using ADB, use a short-lived
mode-`600` file under Termux private app data and remove it after use.

## Routine updates

Use nixpp for later profile updates; do not clear app data or rerun first-run
initialization to add packages.

- Run `nixpp doctor` to inspect configuration, Niks3 access, rbw credentials,
  and configured builders. The builder checks run concurrently; report their
  captured results in a stable, sorted order and omit builder Nix versions.
- Run `nixpp upgrade` to build the configured flake on an available builder,
  fetch its published bundle from the configured S3 substituter, verify it,
  and activate a new generation. `nixpp fetch latest` is an alias for this
  operation. The config is `~/.config/nixpp/config.toml`; it provides the
  flake, builders, trusted public keys, Niks3 substituter, and rbw credential
  command.
- `nixpp upgrade --dry-run` preflights and diffs a candidate without
  activation. After an upgrade, inspect the generation diff.
- `nixpp cache list [--json]` checks the configured Niks3 pins for device
  bundles. It lists configured pins, not every historical NAR retained by the
  cache. It needs the configured S3 credentials and trusted public keys.
- Use `nixpp status`, `nixpp generations`, `nixpp diff`, and `nixpp rollback`
  to inspect or recover generations. Preview cleanup with `nixpp gc
  --dry-run` before running `nixpp gc`.

The bundle's `termux.packages` are Termux APT packages; generated Android/Bionic
programs belong in the nixpp bundle. Do not install Linux/glibc outputs or
copy files that retain Nix store references into the Termux environment.

## Tasker and background jobs

The nightly Termux update runs from Tasker in a nonstandard, often
noninteractive context. Keep its script yadm-managed. Avoid TTY-dependent
prompts, assume neither the interactive login shell nor its current directory,
and propagate `nixpp upgrade`'s exit status so Tasker can detect failures. Do
not put credentials in the script; nixpp gets Niks3 credentials from rbw at
runtime. Keep output concise and capture command output before sorting or
presenting it so messages stay in the right order.

## Verify both layers

After setup or recovery, verify independently:

1. `nixpp status --json` reports a current generation and no invalid
   generations.
2. The yadm checkout exists, `yadm status` works, the `termux` and `nixpp`
   local classes are configured, and yadm bootstrap completed.
3. `command -v yadm` and `command -v zhj` resolve; a simple `zhj` command
   works with the managed Zsh configuration.
4. Relaunch Termux and confirm it starts the managed shell.

Before `nixpp switch`, verify the builder's SSH host key from trusted data and
confirm the phone's SSH identity can reach it. Keep host-key checking enabled.
Preserve the initializer's recovery copy until the new package tree, nixpp
generation, yadm setup, and relaunch have all been verified. Restore it only
when the user asks for rollback.
