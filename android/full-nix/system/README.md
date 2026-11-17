# Declarative guest system

This is an experimental system-generation assembly layer beneath Home Manager.
It does not replace Android, run systemd, or claim NixOS compatibility. It is not
activated on devices. The manifest explicitly records `activationSupported: false`;
there is no switch command yet, and the outputs must not be installed as a NixOS
system profile.

## Interface

`termuxppConfigurations.<host>.system` builds a guest system closure containing:

- `sw`: independently selected guest-system packages;
- `etc`: declarative system files with safe relative paths;
- `home-manager`: the existing HM generation associated with this system;
- `manifest.json`: a versioned description of identity, runtime and child HM generation.

The two experimental host outputs preserve the existing `homeConfigurations`
unchanged. Core packages temporarily exist in both layers until activation and
session PATH ownership are migrated together. The build is assembly-only: it
neither edits the live guest filesystem nor activates Home Manager.

```sh
# On a disposable worker, with the normal private-input authentication:
nix build '.#termuxppConfigurations.zf10.system'
nix build '.#termuxppConfigurations.p11.system'
```

## Candidate sessions and command naming

The user-facing interface is named **`nixpp`**, recycling the native tool's name.
The native recovery tool is not replaced by this experimental guest package.
`sw/bin/nixpp` currently implements only candidate preparation:

```sh
# Inside the guest, after the candidate closure has been fetched without local builds:
/nix/store/HASH-termuxpp-system-HOST/sw/bin/nixpp prepare \
  --runtime /android/ABSOLUTE_NATIVE_RUNTIME_DIRECTORY \
  /nix/store/HASH-termuxpp-system-HOST
```

This validates schema, runtime ABI, identity and required session paths, then
materializes a private `/etc` snapshot and a data-only session descriptor under
`system-candidates/HASH-termuxpp-system-HOST/` in the native runtime directory.
Declared files overlay existing runtime defaults. Android-owned `passwd` and
`group` cannot be overridden; symlinked directories and special files are
rejected. File symlinks are materialized inside the guest so native startup does
not need to resolve virtual store links. A direct Nix GC root retains the system
closure, including its linked HM generation. Existing candidates are never
overwritten, and a failed copy is not published.

The matching TermuxPP runtime accepts `session.sh --system CANDIDATE -- COMMAND`.
It loads the six-line descriptor as data, checks identity and paths, and selects
the physical candidate `/etc` plus system PATH for that invocation only. Normal
and bootstrap sessions retain their existing defaults. Candidate sessions still
share the persistent home; use the runtime checker's isolated candidate mode,
not real vault or cloud operations, for acceptance. Neither preparation nor
launch runs HM activation. These paths are worker-tested, not Android-qualified.

No `switch`, `rollback`, generation listing or NixOS compatibility alias is
advertised yet. Build/rebuild commands and persistent generation selection must
be added with the coordinated activation protocol below, not by renaming the
legacy native executable or manufacturing a NixOS profile.

## Upstream assessment

Reviewed nix-on-droid at revision
[`3264519d7df25f82e716e83607acf5e61f89b1ea`](https://github.com/nix-community/nix-on-droid/tree/3264519d7df25f82e716e83607acf5e61f89b1ea/modules).
Its Nix module evaluation, separate system path, declarative `/etc`, generation
profile and child HM activation are the relevant architectural model. Its
[`build/activation.nix`](https://github.com/nix-community/nix-on-droid/blob/3264519d7df25f82e716e83607acf5e61f89b1ea/modules/build/activation.nix)
builder directly includes proot-static and runtime-specific login programs.
Those cannot be imported unchanged into the droid-nix launcher integration.
This prototype uses Nixpkgs `lib.evalModules` and the existing public HM API;
it does not vendor upstream implementation or add a second execution runtime.

## Activation requirements before migration

A production switch must coordinate these as one system operation:

1. Verify candidate closure and runtime compatibility before writes.
2. Prepare a versioned system `/etc` and system PATH without overwriting native
   recovery or Android-managed networking/certificate inputs.
3. Activate the associated HM generation under the correct guest identity.
4. Run active acceptance and record partial failures accurately.
5. Publish the system profile and the native launcher's generation selection
   with explicit crash-recovery semantics.
6. Support listing and selecting retained system generations, including the
   matching HM generation and runtime compatibility constraints.

The default launcher still binds the original physical `root/etc` directory and
reads native `session.env`; neither automatically follows this system output.
Explicit candidate launch is available, but persistent selection needs a
coordinated runtime change before activation is supported.
A profile symlink alone would not change the session or provide safe rollback.
Service supervision, native API command packaging and a rebuild frontend are
also separate from this assembly milestone. Existing recovery and old HM
profiles remain authoritative during the transition.
