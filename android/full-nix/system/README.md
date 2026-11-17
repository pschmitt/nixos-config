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

The current launcher binds a prepared physical `root/etc` directory and reads
native `session.env`; neither automatically follows this system output. These
interfaces need a coordinated runtime change before activation is supported.
A profile symlink alone would not change the session or provide safe rollback.
Service supervision, native API command packaging and a rebuild frontend are
also separate from this assembly milestone. Existing recovery and old HM
profiles remain authoritative during the transition.
