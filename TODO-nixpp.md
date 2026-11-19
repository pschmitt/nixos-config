# nixpp and TermuxPP TODO

## Android app

- [x] Fix RBW fingerprint unlock on the managed Android guests. Coordinate
  with the RBW enrollment work and distinguish a blocked biometric prompt
  from a Keystore signing error after authentication. Use a disposable
  authentication-bound signing key to verify the TermuxPP API path on both
  phones before testing RBW with the existing enrollment.
  2026-11-19: the API path is verified on p11 and zf10 with a disposable
  hardware-backed key (generate, `list -d`, delete; sign without
  authentication returns an empty signature within 0.3 s instead of
  hanging). Hangs after the master password came from the frozen
  `:background` process owning the am socket (termuxpp a319a9e0); rbw now
  times out every Keystore call (rbw 62aa5ee). Enrollment with a real
  fingerprint succeeded on p11 (hardware-backed, authentication-bound key,
  300 s window).

- [x] Merge TermuxPP:API into TermuxPP. Review droid-nix for guest integration
  patterns. Verify a real API call from the app terminal and from an SSH session
  in the managed Nix guest.
- [x] Merge TermuxPP:Tasker into TermuxPP. Verify that a Tasker action enters the
  managed Nix guest and returns its output and exit status.
- [x] Inventory the remaining TermuxPP companions and integrate them into the
  main APK. Preserve permission and caller checks and document any migration
  needed for installed companion apps and existing automation.

- [x] Let users bind an arbitrary command and its arguments to TermuxPP gesture
  actions, including taps and extra-keys swipes. Define the execution context
  for native and Nix sessions and let users choose the action in Settings.

## nixpp

- [x] Restore `nixpp upgrade` for remote builds and managed guest activation.
- [x] Restore signed, cache-only upgrades with `nixpp upgrade --from-cache`.
- [x] Inventory the other legacy commands, flags and diagnostics. Port the
  relevant behavior to the guest CLI and verify it against installed systems.
- [x] Add `nixpp gc --keep-generations 3` and `--dry-run`. Protect the active
  and rollback generations, generations used by running guest sessions, and
  any interrupted activation. Keep enough history for signed cache pin checks
  to recognise an older generation after pruning. Run GC under the controller
  lock, then wire it into nightly maintenance after a successful upgrade.
- [x] Add `nixpp diff` for closure changes between retained generations. With
  no arguments, compare the previous generation to the active generation.
- [x] Support `nixpp enter --outer` in SSH and other sessions without a
  per-terminal native parent. Have the native supervisor serve a separate
  same-UID Unix socket under `/run/nixpp-runtime`. Relay a dedicated native
  PTY for interactive sessions and
  preserve separate stdio streams for non-interactive commands. Test `rish`
  over SSH, terminal resize, Ctrl-C, exit status and disconnect cleanup.
- [x] Use a Shizuku fallback for zsh helpers that need the phone's route,
  gateway or source IP. The Nix-managed `ip` wrapper provides route, address
  and neighbour JSON on the phones. `whatsmy gateway` and `whatsmy ip` passed on
  both devices, and other hosts keep their normal Linux `ip`.

## Bootstrap

- [x] Ship a simple second-stage launcher in the TermuxPP bootstrap ZIP. Have
  it fetch and run yadm-init from `https://y.brkn.lol` and let yadm-init handle
  credentials at runtime. Keep the ZIP free of embedded credentials and test
  the launcher from a fresh install.

## Services

- [x] Add declarative service definitions for the managed Nix guest, with
  supervision and a Termux `svc`-style CLI for status, start, stop, and restart.
  Add a page in TermuxPP settings for the same controls and service logs.

## Architecture redesign

See [docs/termuxpp/architecture.md](docs/termuxpp/architecture.md) for the
layers, failure causes and principles.

- [x] Controller watchdog in `TermuxService`; child process limit in
  `termuxpp-setup-permissions` and disabled on both phones.
- [x] Stable redirect library at `files/lib/libtermux-pkg-redirect.so`; nixpp
  compares the preload by file identity, not by spelling.
- [x] Redirect `files/apps/com.termux` so stock `termux-am-socket` works.
- [x] One sshd: native Termux sshd off (runit `down` file), Home Assistant's
  Tasker launcher drives the guest's runit sshd through `svc`.
- [x] Tasker plug-in service mode: pick a guest service, start/stop/restart.
- [x] One app-owned native daemon (first stage: `nixpp serve` runs the outer
  socket, service supervision and the bridge as threads; logins only start
  it; guest trees retire with their daemon). Follow-up: controller, outer socket,
  service supervision and the android bridge as threads of one process the
  app starts and the watchdog checks. One lock, one restart path, one APK
  update reaction, fewer phantom processes.
- [x] One login path for terminal, SSH, ADB shell, Tasker, `nixpp enter` and
  `session.sh`, with the environment from one source the app writes.
- [x] No long-running `run-as` processes; `run-as` only for one-shot
  diagnosis and recovery in `termuxpp-adb-shell`.
- [x] One guest-to-Android channel: an in-app socket (am protocol plus API
  calls, authorized by peer UID) replacing the Termux:API broadcast path, the
  python android bridge and `outer.sock` where possible.
- [x] Update-transition tests: new APK on an old runtime and the reverse.
  Covered at the decision points: nixpp's `marker_differs` over every
  APK/script combination (at most one restart, path spellings settle) and the
  app's start-script detection (`NixppRuntimeRecoveryTest`).
- [x] End-to-end transition test: `pkgs/nixpp/tests/test-start-transitions.sh`
  (in `nixpp-system-tests`) runs the real `start-system-control.sh` on a fake
  Android root through app updates, a downgrade to an app without the stable
  copy and back, and asks the real nixpp (`__apk-replaced`) whether serve
  would restart. It found a restart loop after such a downgrade: the script
  now follows the library the app records.

## CLI

- [ ] Sporadic `eza -d` "hang" in the candidate self-test on p11 (37 s and
  607 s, both on 2026-11-19; `nix` and `rsync` were slow in the same runs).
  Likely cause: the daemon ran in the cgroup of the `:background` (Tasker)
  process, which Android freezes while cached, freezing the whole check
  including its timer; `eza -d` was simply running at the time. Fixed in the
  app (termuxpp a319a9e0: app-wide setup, including the nixpp watchdog, only
  in the main process); the daemon now warns when it runs in a secondary
  process's cgroup. Close after a week of switches without a timed-out check.
- [x] `termuxpp-self-update`: update the TermuxPP APK from the CLI, like
  Settings > About does (same release source and checks; Android shows the
  install prompt, or Shizuku installs without one).

## Acceptance

- The combined APK installs alongside the old companions. With the old
  companions disabled, the integrated API returned battery status and the
  Tasker action returned guest stdout, stderr, and its exit code.
- The battery command passed in the app terminal, over SSH, and in the native
  TermuxPP shell.
- An isolated runtime on the Android handset completed enrollment through
  `nixpp-setup` and verified the yadm checkout. The same runtime installed
  a later system using only the signed S3 cache.
- The active handset system runs supervised SSH. The service controls passed
  on-device, and the settings page displayed the SSH listener logs.
