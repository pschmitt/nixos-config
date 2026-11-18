# Rust replacement contract

The deliverable is a standalone Rust executable, compiled separately for the
Linux/glibc guest and Android/Bionic native runtime. There are no Python bindings
and no delegation to a Python implementation of setup or system management.
Upstream Nix, Home Manager activation and the droid-nix launcher remain external
runtime dependencies.

## Observable boundaries

Parity is measured at candidate filesystem artifacts, persisted controller state,
management socket requests and responses, subprocess arguments, and exit status.
The reference implementations are the guest `system/prepare-session.py` and
runtime `system-control.py` from the experimental full-Nix branches.

Required preserved behavior includes:

- Validated store paths, candidate names, manifests, runtime and numeric identity.
- Private staging, no candidate overwrites, physical etc snapshots and direct GC roots.
- Same-UID socket authorization, bounded messages and serialized mutations.
- Isolated checks before activation; old and proposed system/Home Manager pairs
  journaled before mutations; matching activation and upstream profile reconciliation.
- Failed or interrupted activation retains its journal and blocks another switch.
- Recovery uses the old environment and retains the journal if recovery fails.
- Process-group cleanup on timeout or cancellation, without killing other sessions.
- Build commands disable local compilation; native recovery requires no guest socket.

Human-facing wording, help layout and terminal colors intentionally change.
JSON remains free of terminal escapes. The Rust protocol rejects boolean status
values rather than treating Python's `True` as integer `1`; typed controller state
requires all four state keys. The service bounds responses to 65536 bytes and
uses a five-second request deadline. These stricter validation boundaries need
explicit integration coverage; they are not claimed as exact Python parity.
Native direct commands move under
`nixpp controller`; setup moves under `nixpp init`. These are documented interface
changes, not byte-for-byte CLI compatibility with the former helper scripts.

## Verification and cut-over

Run Rust unit tests, formatting and Clippy remotely. Run compiled CLI black-box
protocol tests and system assembly tests. Compare reference and replacement over
the same fixture inputs, recording the number compared and any differences.
Build both target ABIs before on-device acceptance. Qualify native direct recovery,
service/client integration, activation, rollback and interrupted activation on the
test device before migrating an everyday device.

Delete obsolete production Python setup/controller entry points only after their
callers and tests are migrated. Reference fixtures may remain explicitly test-only.
The older Rust native bundle manager is a different product contract: existing
unmigrated bootstrap/recovery consumers remain supported during migration, but
migrated full-Nix hosts must not use it as a second configuration layer.

## Legacy cleanup after both phone migrations

After both phones are migrated and native recovery is verified, remove legacy
code and configuration that no longer has a live consumer. This includes the old
bundle-manager implementation and exports, obsolete Python setup/controller
entry points, superseded outer-layer configuration and packages, migration-only
launchers, and stale documentation or tests. Audit callers before deletion and
update any remaining bootstrap/recovery consumer to its proven replacement.
Retain the minimal native substrate and data needed for independent recovery;
retirement must not remove the only working recovery path.

The optional Android API bridge and a general Termux package bridge are outside
this port's system-management protocol. No arbitrary native command operation is
added to that protocol.
