# Declarative guest system

This experimental system layer sits beneath Home Manager on the droid-nix
runtime. It does not replace Android, run systemd, or claim NixOS compatibility.
Assembly, candidate preparation and the management protocol have worker tests;
the coordinated activation path is not yet Android-qualified.

## Interface

`termuxppConfigurations.<host>.system` builds a closure containing:

- `sw`: independently selected guest-system packages and `nixpp`;
- `etc`: declarative system files with safe relative paths;
- `home-manager`: the matching HM generation;
- `manifest.json`: versioned identity, runtime, session and child HM metadata.

An associated HM generation enables `activationSupported`; a system without HM
can be assembled and prepared but cannot use coordinated activation. Existing
`homeConfigurations` outputs remain available during migration. Core packages
currently overlap between the two layers; activation selects system configuration
and packages together with the associated HM generation.

Build full closures on a disposable worker and publish them directly to the
cache. Never compile them on the workstation or phone:

```sh
nix build '.#termuxppConfigurations.zf10.system'
nix build '.#termuxppConfigurations.p11.system'
```

## Guest command: nixpp

The user-facing interface is **`nixpp`**, recycling the native tool's name without
replacing the independently retained native recovery tool.

```sh
# In the guest, with the matching native controller running:
nixpp list-generations
nixpp check HASH-termuxpp-system-HOST
nixpp switch HASH-termuxpp-system-HOST
nixpp rollback
nixpp recover

# Builds disallow local compilation; use configured remote builders:
nixpp build --flake /path/to/config --host HOST
nixpp rebuild --flake /path/to/config --host HOST
# Alternatively lease a worker through the existing rworker-nix integration:
nixpp rebuild --flake /path/to/config --host HOST --rworker
```

`build` returns a store path. `rebuild` builds, prepares a candidate if needed,
then requests a coordinated switch. `--max-jobs 0` prevents phone-side compilation
when using normal builders; `--rworker` uses the existing wrapper which enforces
the same policy. The chosen remote builder must already be configured and trusted.
This is a guest-system rebuild, not `nixos-rebuild` or Android OS management.

`NIXPP_RUNTIME` supplies the native runtime directory through `/android`;
`NIXPP_SOCKET` supplies the guest-visible management socket. The launcher sets
both. `rebuild --runtime PATH` can override the former. The native service runs
outside the guest, permits only same-UID clients and fixed management operations,
and executes no arbitrary client-supplied native command.

## Candidate preparation

```sh
/nix/store/HASH-termuxpp-system-HOST/sw/bin/nixpp prepare \
  --runtime /android/ABSOLUTE_NATIVE_RUNTIME_DIRECTORY \
  /nix/store/HASH-termuxpp-system-HOST
```

Preparation validates schema, runtime ABI, identity and required session paths,
then materializes a private `/etc` snapshot and six-line data descriptor under
`system-candidates/HASH-termuxpp-system-HOST/`. Declared files overlay runtime
defaults. Android-owned `passwd` and `group` cannot be overridden; symlinked
directories and special files are rejected. Regular file symlinks are materialized
inside the guest so native startup need not resolve virtual store links. A direct
GC root retains the system closure and its matching HM generation. Candidates
are never overwritten, and failed copies are not published.

Explicit `session.sh --system CANDIDATE -- COMMAND` uses that candidate without
selecting it or activating HM. Sessions share the persistent home and store;
they are not disposable homes or a security sandbox. Acceptance uses isolated
fixtures, not real vault authentication or cloud operations.

## Activation and recovery

The matching native TermuxPP controller serializes mutations with a lock:

1. Validate the retained candidate and run thorough isolated acceptance in a
   fresh session using its `/etc` and system package path.
2. Persist a journal recording the old and proposed system/HM pair.
3. Activate the associated HM generation in that fresh candidate environment.
   Its existing activation hooks include preflight and active acceptance.
4. Repeat candidate acceptance and atomically publish default system selection
   and generation state. Remove the journal only after publication succeeds.

First migration requires a verified old HM generation, passed to the native
controller's `switch --previous-home-manager STORE_PATH`. A direct GC root retains
that baseline. Subsequent guest `nixpp switch` operations use recorded state.

Activation cannot make arbitrary HM file changes atomic. Failure or interruption
after journaling leaves the operation pending and blocks another switch.
`nixpp recover` explicitly reactivates the journal's old HM generation in its
old system environment and restores selection. Failed recovery retains the
journal. If the guest cannot start, invoke the native controller from recovery.

`rollback` activates the retained previous pair, including the original HM-only
baseline after the first migration. Prepared system GC roots retain matching
closures; this implementation does not garbage-collect candidates or backups.
New default sessions follow `current-system`; existing sessions are not replaced.
`--legacy` ignores selection and uses original runtime configuration, while
`--bootstrap` always retains independent native bootstrap recovery. A NixOS
`system` profile is deliberately not fabricated.

The native controller starts only when its `system.enabled` marker is installed.
See the matching TermuxPP runtime README for staging and recovery commands. Do
not enable the migration merely because worker tests pass: verify first-switch,
fresh-login, rollback and recovery behavior on the authorized test device before
migrating another phone. Native service supervision and Android API integration
are separate concerns.

## Secrets (sops-nix)

Both layers can install secrets with the pinned upstream
[sops-nix](https://github.com/Mic92/sops-nix) installer; there is no systemd, no
root and no daemon. The system layer (`system/sops.nix`) reuses the pinned upstream
Home Manager module for every `sops.*` option (including templates), its assertions,
its manifest and its installer script. It is evaluated against inert option sinks
for the few Home Manager and systemd options that module writes; nothing reads
them and no systemd is run or faked. The installer script is read from the unit's
`ExecStart`, and `sops.environment` is applied from its literal values. Home
Manager keeps its own `sops.*` (see `../README.md`).

**Contract with the runtime.** The manifest gains an optional field

```json
"systemSecrets": "/nix/store/<hash>-activate-secrets/bin/activate-secrets"
```

and the toplevel exposes the same executable as `bin/activate-secrets` (a symlink).
It is present only when `sops.secrets` is not empty, and absent otherwise and in
older generations. The controller runs it with no arguments in the freshly selected
candidate environment, after the journal is persisted and before the matching Home
Manager `activate`, for switch, rollback and recover. A non-zero exit fails the
activation, so no Home Manager mutation happens after a failed system secret
install. It uses `$XDG_RUNTIME_DIR` when set and falls back to
`fullNix.sops.runtimeDir` (`/tmp/run`, matching the guest shell). It is idempotent
and re-runnable for recovery.

**Separate namespaces.** The system layer uses `%r/termuxpp-system/sops-nix/secrets`
(link) and `%r/termuxpp-system/secrets.d` (generations); Home Manager uses
`~/.config/sops-nix/secrets` and `%r/secrets.d`. Both run as the same Android UID,
so this is organization, not a security boundary: file modes are the only access
control.

**Stale secrets and baseline.** Cleanup is upstream's and there is no state of ours.
A secret dropped from a still-configured set disappears with the pruned generation
(`keepGenerations`); its custom `path` symlink dangles. Removing every secret
leaves no hook, so nothing runs and the previously installed data stays until
removed by hand; the same holds for rolling back to a generation without
`systemSecrets` (for example the original HM-only baseline). A changed
`runtimeDir` is a different location and the earlier one is not touched. Revocation
is therefore not guaranteed by activation.

**Limits.** Decrypted secrets live under `$XDG_RUNTIME_DIR`, which is `/tmp/run`:
persistent app storage in the guest, not tmpfs. They are not in the Nix store, but
they do survive reboots until removed. `sops.environment` values are literal strings
(not pre-quoted as for systemd units). `home.nix` imports `sops.nix`, which adds
nothing to a guest without secrets.

Tests: `../sops-tests.nix` (ephemeral age key and synthetic sops file generated
inside the build) covers install, modes, templates in both layers, namespace
separation, the `%r` fallback, the exact `systemSecrets` hook in the built manifest,
failure propagation (wrong or missing key keeps what is installed), a removed
secret, the retained data when every secret is removed, upstream's assertions and no
systemd; it also evaluates the real `zf10` and `p11` configurations. Run it on a
worker:

```sh
nix build --impure --no-link -L --expr \
  'import ./android/full-nix/sops-tests.nix { inputs = (builtins.getFlake (toString ./.)).inputs; }'
```

## Upstream assessment

Reviewed nix-on-droid at revision
[`3264519d7df25f82e716e83607acf5e61f89b1ea`](https://github.com/nix-community/nix-on-droid/tree/3264519d7df25f82e716e83607acf5e61f89b1ea/modules).
Its Nix module evaluation, separate system path, declarative `/etc`, generation
profile and child HM activation are the relevant architectural model. Its
[`build/activation.nix`](https://github.com/nix-community/nix-on-droid/blob/3264519d7df25f82e716e83607acf5e61f89b1ea/modules/build/activation.nix)
builder directly includes proot-static and runtime-specific login programs.
Those cannot be imported unchanged into the droid-nix launcher integration.
This implementation uses Nixpkgs `lib.evalModules` and the existing public HM
API; it does not vendor upstream implementation or add a second guest runtime.
