# nixpp and TermuxPP TODO

## Android app

- [ ] Merge TermuxPP:API into TermuxPP. Review droid-nix for guest integration
  patterns. Verify a real API call from the app terminal and from an SSH session
  in the managed Nix guest.
- [ ] Merge TermuxPP:Tasker into TermuxPP. Verify that a Tasker action enters the
  managed Nix guest and returns its output and exit status.
- [ ] Inventory the remaining TermuxPP companions and integrate them into the
  main APK. Preserve permission and caller checks and document any migration
  needed for installed companion apps and existing automation.

## nixpp

- [ ] Restore legacy upgrade workflows for managed guest generations. Finish
  validating the remote build and switch path and restore signed, cache-only
  upgrades.
- [ ] Inventory the other legacy commands, flags and diagnostics. Port the
  relevant behavior to the guest CLI and verify it against installed systems.

## Bootstrap

- [ ] Ship a simple second-stage launcher in the TermuxPP bootstrap ZIP. Have
  it fetch and run yadm-init from `https://y.brkn.lol` and let yadm-init handle
  credentials at runtime. Keep the ZIP free of embedded credentials and test
  the launcher from a fresh install.

## Services

- [ ] Add declarative service definitions for the managed Nix guest, with
  supervision and a Termux `svc`-style CLI for status, start, stop, and restart.
  Add a page in TermuxPP settings for the same controls and service logs.
