# nixpp and TermuxPP TODO

## Android app

- [x] Merge TermuxPP:API into TermuxPP. Review droid-nix for guest integration
  patterns. Verify a real API call from the app terminal and from an SSH session
  in the managed Nix guest.
- [x] Merge TermuxPP:Tasker into TermuxPP. Verify that a Tasker action enters the
  managed Nix guest and returns its output and exit status.
- [x] Inventory the remaining TermuxPP companions and integrate them into the
  main APK. Preserve permission and caller checks and document any migration
  needed for installed companion apps and existing automation.

- [ ] Let users bind an arbitrary command and its arguments to TermuxPP gesture
  actions, including taps and extra-keys swipes. Define the execution context
  for native and Nix sessions and let users choose the action in Settings.

## nixpp

- [x] Restore `nixpp upgrade` for remote builds and managed guest activation.
- [x] Restore signed, cache-only upgrades with `nixpp upgrade --from-cache`.
- [x] Inventory the other legacy commands, flags and diagnostics. Port the
  relevant behavior to the guest CLI and verify it against installed systems.
- [ ] Add `nixpp gc --keep-generations 3` and `--dry-run`. Protect the active
  and rollback generations, generations used by running guest sessions, and
  any interrupted activation. Keep enough history for signed cache pin checks
  to recognise an older generation after pruning. Run GC under the controller
  lock, then wire it into nightly maintenance after a successful upgrade.
- [ ] Support `nixpp enter --outer` in SSH and other sessions without a
  per-terminal native parent. Have the native supervisor serve a separate
  same-UID Unix socket under `/run/nixpp-runtime`, with access selected by the
  phone profile. Relay a dedicated native PTY for interactive sessions and
  preserve separate stdio streams for non-interactive commands. Test `rish`
  over SSH, terminal resize, Ctrl-C, exit status and disconnect cleanup.

## Bootstrap

- [x] Ship a simple second-stage launcher in the TermuxPP bootstrap ZIP. Have
  it fetch and run yadm-init from `https://y.brkn.lol` and let yadm-init handle
  credentials at runtime. Keep the ZIP free of embedded credentials and test
  the launcher from a fresh install.

## Services

- [x] Add declarative service definitions for the managed Nix guest, with
  supervision and a Termux `svc`-style CLI for status, start, stop, and restart.
  Add a page in TermuxPP settings for the same controls and service logs.

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
