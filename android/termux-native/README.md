# Native Termux environments built with Nix

## Recommendation

Use Nix on the build server to produce **Android/Bionic artifacts**, cache those
outputs in your normal Nix cache, and export a Termux install bundle. Sign the
release before distributing it beyond a trusted channel.
The phone needs a small installer, not Nix, Ansible, a compiler, or proot.
Let Termux APT provide packages already in its repositories. Use the versioned
bundle for generated configuration, shell plugins, and custom binaries that
aren't already practical to install from Termux.

The package and profile are part of the repository's root flake, so they share
its pinned Nixpkgs and Home Manager inputs. The regular CLI profile and Termux
both import `home-manager/cli/core.nix`, which composes their shared bat, eGet,
eza, fd, ripgrep, tmux, and Zsh modules. Those modules keep their normal Nix
package behavior on Linux; in Termux mode they render the same settings and
select Termux packages or exported Android binaries. Neovim uses the regular
host module on Linux and a portable Termux module on Android. The Termux
profile supplies the Termux identity and package selection, while the exported
HM module handles Termux-specific package and file export rules.

## Use the profile

The reusable module is exported as
`inputs.nixos-config.homeManagerModules.termux`. Add it only to the Home Manager
user for a Termux environment:

```nix
{ inputs, lib, ... }:
{
  imports = [ inputs.nixos-config.homeManagerModules.termux ];

  # Termux applications are APT packages; Home Manager renders their config.
  termux.packages = lib.mkAfter [ "ripgrep" ];
  termux.homeFiles = lib.mkAfter [ ".config/nvim/lua/user.lua" ];
  xdg.configFile."nvim/lua/user.lua".text = ''
    vim.opt.number = true
  '';
  programs.tmux.extraConfig = lib.mkAfter ''
    set -g mouse on
  '';
}
```

`termux.packages` declares the Termux package names required by this profile.
The bootstrap installs these through `pkg`, so Termux APT resolves dependencies,
tracks package ownership, and handles future updates. Home
`home.packages` remains the standard Home Manager option for packages that
produce Android/Bionic binaries without Nix store references. The standalone
profile uses it for nixpp. Mark such derivations with
`passthru.termuxNative = { files = [ "bin/tool" ]; binaries = [ "bin/tool" ]; };`.
The exporter preserves declared package files under the generation, creates
command launchers, and checks that each executable is AArch64 ELF with an
Android linker (or is static), and only needs Android API 24 system libraries
or libraries included in that package's `lib` or `lib64` export. Unsupported
`home.packages` entries fail the build with guidance to use `termux.packages`
for Termux APT packages or add an Android/Bionic export contract. Home
Manager's own support packages are handled separately. The final generation
rejects Nix store references. Linux executables cannot run in native Termux.
`termux.homeFiles` is an export allowlist: only those generated files enter the
archive. Keep private dotfiles out of this public bundle; add a path to the
allowlist only when you intend that file to ship.

The complete Termux Home Manager module is
`modules/home-manager/termux.nix`, exported as
`homeManagerModules.termux`. It sets Termux's home identity, imports the shared
CLI modules, selects the Termux APT packages, and declares the allowlist used
by this bundle. The bundle builder evaluates that same exported module.

Build the ready-to-install bundle on an x86_64 Linux builder (use `rofl-13` or
`rofl-14`, not the phone):

```sh
nix build '.#termux-native-bundle'
sha256sum result/environment.tar.gz
```

Use the official [Termux package recipes](https://github.com/termux/termux-packages)
for Termux-native package builds. Keep those packages in the Termux APT
repository flow; the Nix bundle does not copy or install `.deb` files.

The result contains `environment.tar.gz`, `bootstrap.sh`, and `activate.sh`.
Transfer all three to the phone through a trusted channel. In Termux, after
`termux-setup-storage`, run:

```sh
cd ~/storage/downloads
bash bootstrap.sh install environment.tar.gz TRUSTED_SHA256
termux-native-status
```

Use the digest obtained directly from the trusted builder. The adjacent
`SHA256SUMS` file is useful for checking accidental corruption, but is not a
signature. To roll back, pass the previous generation's 64-character digest to
`bash activate.sh rollback SHA256`.
To restore the Termux zsh startup file, run `bash bootstrap.sh restore`; installed
generations remain available until you remove them yourself.

```text
Home Manager config + pinned root flake inputs
             |
     Linux builder + Android NDK
             |
     Nix output / binary cache
             |
     release exporter
             |
   HTTPS bundle + trusted digest
             |
 Termux: verify -> unpack -> smoke test -> switch current symlink
```

## What Nix can and cannot provide

Cross-compilation to Bionic is supported in principle and for suitable packages.
Nixpkgs exposes Android platform definitions including
`aarch64-android-prebuilt`. This is **not** a promise that arbitrary Nixpkgs
packages, or Home Manager modules, build and run on Android. Ordinary
`aarch64-linux` packages target a different libc and environment.
See [Nixpkgs Android platform definitions](https://github.com/NixOS/nixpkgs/blob/master/lib/systems/examples.nix).

There are two useful build approaches:

- Use a Nixpkgs Android cross package set and override packages for Android,
  API level, paths, and dependencies. Audit compiler wrappers and resulting ELF
  files; do not assume cross-compilation makes an output relocatable.
- Use a Nix-packaged Android NDK directly inside a derivation. This prototype
  uses that approach: Linux build tools produce an AArch64 executable against
  Bionic for API 24. This makes the compiler target and runtime dependencies
  explicit. See [the NDK guide](https://developer.android.com/ndk/guides/other_build_systems).

A binary cache can store either output, including an entire assembled
environment. But it stores NAR objects and reference metadata, not a portable
installation transaction. Native Termux does not have `/nix/store`, and moving a
normal closure under `$HOME` does not rewrite its interpreters, RPATHs, symlinks,
or compiled-in file names. The [Nix store-path model](https://nix.dev/manual/nix/2.28/store/store-path)
explicitly distinguishes reference-free objects from objects tied to a store
directory.

Use the Nix cache between builders and release exporters. Export the payload
as tarballs or Termux `.deb` packages for phones. Nix signatures do not
automatically authenticate an exported tarball: sign the release manifest too.
A custom native NAR downloader is possible, but must implement verification,
reference traversal, safe extraction, and activation; it still cannot relocate
ordinary closures. A custom store prefix and specially built Bionic closure is
possible as a much larger project, with its own package universe and installer.
It offers little advantage for this onboarding goal.

## Practical architectures

| Architecture | Strength | Cost / limitation |
| --- | --- | --- |
| Termux base + Nix-built generation bundle | Small bootstrap; atomic updates to owned files; simple rollback | Base packages remain independently managed; every bundled binary must be portable within the chosen prefix contract |
| Nix-built Termux `.deb` packages + signed APT repository | Uses Termux dependency resolution, package ownership, and updates | APT updates are not atomic environment generations; package downgrades and configuration rollback need explicit policy |
| Complete fixed-prefix Termux rootfs/bootstrap image | Can preassemble nearly all userspace and package versions | Large release; prefix assumptions; replacing a live `$PREFIX` is unsafe; maintenance and recovery are considerably harder |

The first is the recommended starting point. Gradually move custom utilities
into bundles; retain complex, already-patched software such as zsh, OpenSSH,
Python, Git and OpenSSL as Termux packages until there is a reason to own their
builds. For lots of shared native dependencies, the second approach may become
more economical.

Termux's APT repository is already built from the upstream
[Termux package recipes and patches](https://github.com/termux/termux-packages),
so prefer `pkg install` for packages available there. Reuse those recipes with
the official builder only when a package is missing or needs a custom patch.
When building one package, pass `-I` so dependencies come from Termux's binary
repository instead of rebuilding their full source closure. The Android
executable is installed and tracked by dpkg. This keeps package-specific Android
patches and dependency metadata in the ecosystem that owns them. Making the upstream
network-fetching build scripts hermetic Nix derivations would require modeling
downloads as fixed-output inputs, preventing implicit dependency downloads,
and accommodating the build system's prefix/staging assumptions. See
[Termux build instructions](https://github.com/termux/termux-packages/wiki/Building-packages)
and [package authoring](https://github.com/termux/termux-packages/wiki/Creating-new-package).

For a full userspace image, Termux already provides
[bootstrap archive generators](https://github.com/termux/termux-packages/wiki/For-maintainers).
These are a foundation for provisioning a fresh installation, not an atomic
updater for a running prefix. Do not overwrite dpkg-managed files with a bundle
or unpack multiple fixed-prefix package versions into arbitrary generation
directories and expect them to work. A complete relocatable environment needs
all package data paths and dynamic dependencies adapted, not just its binaries.

## Host responsibilities and lifecycle

The host must initially have a compatible Termux application and bootstrap,
network access, trusted release verification material, and the extraction tools.
For this prototype the base is `bash`, `coreutils`, `tar`, `gzip`, and `zsh`;
production also needs `curl`, CA certificates, and a signature verifier such as
`minisign`. Use `pkg install` for missing base packages. Android permissions,
Termux:API/Termux:Boot companion apps, storage access, and battery policy remain
host concerns. App signing/distribution must be compatible with companion apps.

A production bootstrap should:

1. Check app distribution, prefix, ABI, API floor, available space, and required
   base package versions. Fetch a release manifest over HTTPS and verify it
   against a provisioned trust anchor. Include architecture, API floor, prefix
   contract, bundle hash, base dependencies, and release sequence in the manifest.
2. Download the content-addressed bundle, verify its hash, validate its archive
   entries, and extract into a new generation directory on app-private storage.
   Keep mutable caches and application state elsewhere.
3. Run synchronous, idempotent setup and smoke tests. If they fail, leave the
   current generation untouched. Serialize installers and define recovery for
   interrupted staging/locks.
4. Atomically rename a symlink to select the generation. Start new shells from
   that generation; restart affected services explicitly. Retain old generations
   while processes still use them. Use Termux/runit lifecycle hooks where needed,
   not systemd user units ([termux-services](https://github.com/termux/termux-services)).
5. Record deployment status separately from build success. Retain a small number
   of known-good generations. Rollback selects an earlier generation and restarts
   consumers. It does not reverse data migrations, Android changes, or APT upgrades.

Separate shared role configuration from per-host runtime configuration. A host
selects a role/release channel; nonsecret role files can be built by Nix. Keep
device/account identifiers and credentials out of public artifacts and the Nix
store. Provision SOPS-encrypted host data through an authenticated enrollment
channel and decrypt on the host or trusted provisioning machine. This prototype
optionally sources `$HOME/.config/termux-native/host.zsh` after its shared config.
That file is trusted executable shell configuration, not a sandboxed data format.

The prototype evaluates a narrow Home Manager profile on the Nix builder and
exports selected generated files into a reference-free generation. Its
`termux.packages` option maps required commands to Termux APT packages, and
`termux.homeFiles` lists the rendered files to ship. `home.packages` contains
Android/Bionic outputs declared with `passthru.termuxNative`. The exporter
keeps each package's declared runtime files together, validates its executable
ELF architecture and interpreter, and rejects any final output that retains a
`/nix/store` reference. Home Manager options whose generated files require
store paths, systemd, or Linux-only runtime behavior need a Termux-specific
implementation before they can be used here. Nixpp only fetches and verifies
the finished output; it does not evaluate Home Manager modules.

## Android compatibility boundary

- **ABI and API:** target Android/Bionic, including all native dependencies.
  Build per ABI. Choose a minimum Android API deliberately; build-tool NDK
  version, minimum native API, and the Termux APK's `targetSdkVersion` are
  different settings. Android does not supply glibc, GNU NSS, or all Linux/POSIX
  interfaces. Upstream Linux binaries and downloaded zinit release assets must
  be audited individually.
- **Linking:** use PIE, the Android loader (`/system/bin/linker64` for this ABI),
  public NDK APIs, and Bionic-compatible libraries. Bundle compatible C++ runtime
  libraries when required. Do not ship NDK stub libraries as runtime libraries.
  Inspect `DT_NEEDED`, interpreter and RUNPATH. `$ORIGIN`/`DT_RUNPATH` support
  begins at API 24; each shared library needs suitable lookup for its own direct
  dependencies. Private platform libraries are restricted by linker namespaces.
  See [Android linker changes](https://android.googlesource.com/platform/bionic/+/master/android-changes-for-ndk-developers.md).
- **Paths and scripts:** Termux's normal prefix is
  `/data/data/com.termux/files/usr`. Forked app IDs and alternate Android users
  can break fixed paths. Avoid `/usr`, `/etc`, `/tmp` and Nix store paths in
  runtime assumptions. Use app-private storage; shared storage is unsuitable for
  executable trees and Unix metadata. Call `"$PREFIX/bin/bash" script.sh`
  explicitly or generate a matching absolute shebang. Do not assume
  `#!/usr/bin/env bash` works without Termux's interception layer.
- **Execution policy:** Android API level alone does not determine whether a
  downloaded executable can run. App target SDK, SELinux policy, Termux build,
  and its exec interception matter. Preserve Termux's normal environment,
  including its preload behavior; indiscriminate `LD_LIBRARY_PATH` changes can
  break system commands. See [Termux execution environment](https://github.com/termux/termux-packages/wiki/Termux-execution-environment).
- **Page sizes and services:** support 16 KiB ELF alignment for modern devices,
  and test it on a 16 KiB device/emulator. Native programs remain Android app
  processes subject to background/process limits and permissions. A package
  manager cannot provide root, mount namespaces, unrestricted `/proc`, or a
  durable system service manager. See [NDK build-system guidance](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md).

Static linking can simplify selected leaf tools, but static glibc/musl is not
equivalent to Bionic compatibility. It also loses dynamic `LD_PRELOAD` interception
and does not fix paths, DNS assumptions, permissions, or process execution rules.

## zinit: remove installation from prompt startup

The local dotfiles' `zzinit` helper adds a `wait` ice unless `NO_TURBO_MODE` is
set. It also contains `atclone` helpers that install npm and Go packages. The
Home Manager service already runs `@zinit-scheduler burst` in an interactive
login shell. These observations support the reported prompt dependency, but
are not a full audit of the Ansible bootstrap.

As an interim fix, run provisioning with `NO_TURBO_MODE=1` and explicitly drain
the scheduler, then verify expected plugin files and commands before marking
the bootstrap complete. Direct `zinit wait` declarations and custom hooks still
need inspection. Shell exit status alone is insufficient if a plugin masks an
installation failure. Do not treat an unpinned scheduler-internal command as a
long-term provisioning API.

For the new design, pin plugin sources in Nix, copy their source files into the
bundle, and source them directly or load them locally with a pinned zinit.
Translate network/build hooks into build steps. Keep completion dumps and any
writable zinit state outside generations. Generate completion caches synchronously
with the target zsh if required. Deferred *loading* can remain optional; deferred
*acquisition* must not be required for readiness. The
[zinit documentation](https://github.com/zdharma-continuum/zinit) describes its
deferred-loading and hook facilities.

The prototype demonstrates this boundary with vendored plugins; it does not
yet migrate your full plugin set or run zinit itself.

## Existing foundations

- Nixpkgs Android cross targets and `androidenv`: build-system/toolchain foundation.
- Termux package recipes, APT repositories, bootstrap generators, and services:
  native compatibility and integration foundation.
- [aca/termux-nix](https://github.com/aca/termux-nix): useful declarative Termux
  package/service/config ideas. Its README explicitly puts Nix applications in
  proot; that part does not satisfy this project's native-only constraint.
- Nix cache plus a release exporter: keeps the standard cache protocol on the
  build side and gives devices an ordinary native package format.

## Build details and limitations

Build on `rofl-13` or `rofl-14` from the checked-out repository. The native
project has a locked flake and a small development shell:

```sh
cd android/termux-native
nix build '.#bundle'
nix develop 'path:.' -c statix check
nix develop 'path:.' -c deadnix --fail
nix develop 'path:.' -c shellcheck activate.sh bootstrap.sh test-device.sh
nix-store -q --references result
```

The complete Termux Home Manager module is
`modules/home-manager/termux.nix`, exported by the main configuration flake as
`homeManagerModules.termux`. The bundle evaluates that same module directly,
without resolving the whole NixOS flake graph. The bundle build
copies only `termux.homeFiles` and declared `home.packages` files, then rejects
any Nix store references in the result. It also includes the Termux-native
`gitstatusd`, built with the Android NDK. The Nix cache is a builder-side
optimization; phones receive a tar archive, not NARs or Linux Nix closures.

The profile splits packages by their runtime owner: entries in
`termux.packages` are installed by Termux APT, while Home Manager packages
with a `termuxNative` export declaration are built for Android/Bionic and
copied into the generated profile. It reuses the regular CLI modules for
`bat`, `eget`, `fd`, `ripgrep`, `tmux`, and Zsh. Linux hosts use their normal
Nixpkgs packages. Termux gets Android/Bionic Rust builds of `bat`, `eza`, `fd`,
`ripgrep`, `vivid`, and `zoxide`; `direnv`, `eget`, and `fzf` are built with
the host Go compiler targeting Android/Bionic. Termux APT supplies core and
patched packages such as Neovim and Zsh. Atuin is imported as a pinned Termux
package artifact with its OpenSSL runtime libraries included in the bundle.
Tmux is likewise imported from pinned official Termux package artifacts,
including its runtime libraries, and launched from the managed generation.
These imports remove Atuin and tmux from the Termux APT install list. Nixpkgs'
direct Atuin cross build still fails in OpenSSL on Bionic. The Go toolchain is
patched to use Termux's `/etc` files so those binaries do not refer to the Nix
store. Each exported executable is checked for AArch64 ELF, an Android linker
(or static linkage), and no Nix store references. The profile also shares
portable Neovim options from the regular Home Manager tree.
The regular Linux LazyVim plugin closure is deliberately not included in the
Termux bundle.

The current installer trusts a digest obtained from the builder; it does not
verify a release signature or hostile archive contents. It keeps previous
generations for rollback but does not yet garbage-collect them, enforce an
anti-downgrade policy, or recover interrupted lock directories automatically.
The bootstrap saves the existing `$PREFIX/etc/zshenv` and Termux login shell
before selecting the managed Zsh configuration. A cold app launch then starts
the managed shell directly. `bash bootstrap.sh restore` restores both saved
startup settings without removing installed generations.

## Verification record

On 2026-10-03, an earlier bundle prototype on the Zenfone 10's Termux app installed
official Termux packages `bat` 0.26.1, `fd` 10.5.0, `fzf` 0.74.4,
`grep` 3.12, `procps` 4.0.7, `ripgrep` 15.2.0, `sed` 4.10, `unzip` 6.0,
`zip` 3.0, and `zoxide` 0.10.0. Termux APT installed selected local `.deb` files;
`dpkg-query` and each command reported the expected versions. The generation's
interactive shell smoke test passed. This verifies Termux's package database
and the Nixpp transport/activation path together; other selected tools still
come from the configured Termux repositories.

The profile also declares nixpp in `home.packages`; its static Android/Bionic
executable is copied into each generation. From the Zenfone's Termux app, that
generation's nixpp ran `switch` against rofl-13 and activated generation
`3b7f70e58cbd7c5b203c1f6be6276e7b5c7712468c5f355f7de29991c0ab10b10`. The
Termux display stay-on setting remained enabled. The complete private zinit
configuration is not part of this profile.

On 2026-10-03, the root-flake bundle was rebuilt from the current worktree on
rofl-13 and installed in the Zenfone's official Termux app. A cold app launch
entered the managed Zsh prompt. `fzf` 0.74.4 and `direnv` 2.37.1 resolved from
the active generation's `bin/` directory and ran; neither package was present
in Termux's APT database. The exported Rust tools and `nixpp --help` also ran.
The bootstrap's `restore` and reinstall paths passed, and the generation's
Zsh PTY smoke check passed. The APT package set explicitly updates
`libngtcp2`; `curl --version` succeeded after installation with HTTP/3 support.
No archive was uploaded or published.

The updated profile, importing `home-manager/cli/zsh`, was activated on the
Zenfone through the Termux app UID. Termux APT supplied Atuin, direnv, fzf,
and vivid; the generated Home Manager startup file initialized them at runtime.
Its interactive smoke test passed, including the Atuin widget, direnv hook,
zoxide functions, completions, and the NDK-built `gitstatusd`. The active
generation was `8f857a6c09cea9f3e71a5c89146c761afabf4a429716668f35370c4e47c806d1`.

On 2026-10-03, the updated root-flake bundle built on rofl-13 with zoxide as an
Android/Bionic Home Manager package. Its binary has no Nix-store references
and uses `/system/bin/linker64`; the binary and generated generation launcher
both ran under the Termux app UID on the Zenfone (`--version` and `init zsh`).
The same bundle keeps `fzf` in the APT manifest and removes `zoxide` from it.
The shared portable Neovim options were loaded by Termux's APT Neovim in
headless mode and checked on-device.

The shared CLI module `home-manager/cli/eget.nix` was then imported by the
Termux profile. Its Android Go build was added to the bundle on rofl-13, and
the generated `eget` launcher ran on the Zenfone's Termux app, reporting
`eget version v1.3.4`. The test used the exported launcher and package payload
without installing `eget` through APT. A direct Nixpkgs Android cross-build of
Neovim failed through the `attr` dependency because Bionic headers lack
`IFTODT`; a direct Atuin build failed in OpenSSL on Bionic socket types. Both
were still Termux APT packages at that stage. Neovim remains an APT package;
Atuin was later moved into the bundle below.

An earlier bundle was built on rofl-13 with Nixpkgs' Android cross packages for
`ripgrep`, `fd`, and `bat`. Rust cross builds needed special handling to skip
emulator-based checks and target post-fixup commands, and the generation
launchers were verified on the Zenfone. Since Termux already packages these
tools, the profile uses Termux APT for packages that are difficult to build
or relocate, and retains Nix-built binaries for these four utilities. The
earlier generation digest was
`4b882492cc22e96a252e0efc4b82c1fef5599d522340e386b5eed4c4d118633a`.

Atuin 18.23.0 was moved from `termux.packages` into the native Home Manager
bundle. The Nix package imports Atuin and OpenSSL 3.6.5 from the official
Termux repository using pinned SHA-256 hashes, and exports the OpenSSL runtime
libraries beside Atuin. The Termux package builder on rofl-13 also built Atuin
from its upstream recipe in 5m53s. Activation checks the Atuin launcher and
runs `atuin --version` in the on-device shell smoke test. The Atuin bundle
generation
(`3344efc17ac1064a95c15cbb37e764b588808cf68a760a0e667059c82fe382b7`) was
installed from the interactive Termux app on the Zenfone 10; the generation
smoke test passed and `atuin --version` reported `18.23.0 (NO_GIT)`.
A force-stop followed by launching Termux from its app icon returned to the
managed prompt in about five seconds; the generated shell smoke test then
exited 0 without plugin-fetch output.

A direct Nixpkgs Android cross-build of tmux failed in its Android dependency
graph before producing the package, so the profile now imports tmux and its
runtime libraries from pinned official Termux package artifacts. Neovim remains
a Termux APT package; the shared Home Manager modules still generate its
configuration and keep their Linux package selection unchanged.

The rebuilt tmux bundle `c1177457473d7715bf46e72eb0d13d79258112f2c73f99fa7134a3e399cf8ddc`
was installed from the interactive official Termux app on the Zenfone 10. Its
bootstrap reported that all declared APT packages were already installed (zero
upgrades and installs), then completed the native execution and Zsh PTY checks.
After a force-stop and cold app launch, `tmux` resolved from the active
generation, reported version 3.7c, and created, checked, and killed a detached
session. The bundle's APT manifest does not install tmux.
