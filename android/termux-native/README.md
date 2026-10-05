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
both import `home-manager/cli`, the same entry point. Its modules keep their
normal Nix package behavior on Linux; in Termux mode they render the same
settings and select Termux packages or exported Android binaries. Neovim uses
its regular Home Manager configuration on Linux and a portable Termux
configuration on Android. The Termux profile supplies the Termux identity and
package selection, while the exported HM module handles Termux-specific
package and file export rules.

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
Activation installs these through `pkg` under the generation lock, so Termux
APT resolves dependencies, tracks package ownership, and handles future
updates. Generation rollback changes the selected bundle only; it does not
undo APT transactions or automatically remove packages. No automatic package
removal is implemented, so dependencies shared with another profile or
generation remain safe. Home Manager's `home.packages` remains the standard
option for packages that
produce Android/Bionic binaries without Nix store references. The standalone
profile uses it for nixpp. Mark such derivations with
`passthru.termuxNative = { files = [ "bin/tool" ]; binaries = [ "bin/tool" ]; aptPackages = [ "ca-certificates" ]; };`.
For ordinary Nixpkgs tools, `from-nixpkgs.nix` starts from the regular package
(for example `pkgs.bat`), selects the same package name from
`pkgs.pkgsCross.aarch64-android-prebuilt`, and infers its executable from
`meta.mainProgram`. This builds the Nixpkgs recipe for Android/Bionic instead
of trying to repair a Linux/glibc executable. A package-specific `crossPackage`
can override the Android package when build options differ. The wrapper strips
the executable, then the exporter removes Nix RPATHs and resolves shared
libraries from the Android runtime closure; missing or conflicting
dependencies fail the build.
Stripping uses the selected Android derivation's target `objcopy`, so these
exports do not need a separate host LLVM tool just for ELF stripping.
The extended Android package set exposes reusable constructors under
`termuxAdapters`: `fromNixpkgs` selects and wraps an Android cross derivation,
`fromGo` rebuilds a Nixpkgs Go package for Android, and `pythonApplication`
exports pure-Python packages through Termux's Python. Each result carries the
export metadata the bundle needs; add a package to `home.packages` and unsupported
Nix packages still fail evaluation with a clear diagnostic.
By default, the adapter preserves upstream package hooks and outputs. The
exporter selects only declared runtime files, removes Nix RPATHs, resolves
shared libraries from the Android runtime closure, and cleans ELF metadata for
Termux. This keeps the conversion generic without patching away package build
behavior.
Eza's Pandoc-generated docs and completions are omitted because only its
executable is in the export contract; this avoids building a separate GHC
toolchain for files the archive cannot use.
An upstream hook that executes the Android program during cross compilation
cannot run unless the build host has an Android userspace. Ripgrep's generated
man pages and completions use this pattern, so its `postFixup` is disabled; the
exported Android executable and its runtime dependencies are still validated.
Bat's `postFixup` adds a Nix-specific `less` path to a shell wrapper; that is
disabled too, and the generated Termux launcher uses the Termux `PATH` instead.
The exporter preserves declared package files under the generation, creates
command launchers, and checks every exported ELF for AArch64 and the Android
linker (when it has one). It recursively checks dependencies of both commands
and bundled libraries against Android API 24 system libraries and that
package's `lib` or `lib64` export. It also
installs checked shell scripts using Termux's `sh`, provided they contain no
Nix store paths. Unsupported
`home.packages` entries fail the build with guidance to use `termux.packages`
for Termux APT packages or add an Android/Bionic export contract. Home
Manager's own support packages are handled separately. The final generation
rejects Nix store references. Linux executables cannot run in native Termux.
Pure Python applications can use `python-application.nix`: it copies installed
Python modules from the Nix package, its propagated runtime inputs, and any
explicit `extraRuntimePackages`, removes host-only Python environment metadata
and bytecode, and points a Termux shell launcher at the system Python with the
modules in `PYTHONPATH`.
The exporter rejects ELF files in this data tree and rejects Nix store
references. This works for pure Python packages; packages with native Python
extensions still need an Android build or a Termux APT package.
`termux.homeFiles` is an export allowlist: only those generated files enter the
archive. Keep private dotfiles out of this public bundle; add a path to the
allowlist only when you intend that file to ship.

The complete Termux Home Manager module is
`modules/home-manager/termux.nix`, exported as
`homeManagerModules.termux`. It sets Termux's home identity, imports the shared
CLI modules, selects the Termux APT packages, and declares the allowlist used
by this bundle. The bundle builder evaluates that same exported module.

To build an extended profile, use `lib.termux.mkBundle` and supply additional
Home Manager modules and special arguments. The built-in Termux module remains
the base profile:

```nix
nixos-config.lib.termux.mkBundle {
  modules = [ ./my-termux-profile.nix ];
  extraSpecialArgs = { inherit myPackageSet; };
}
```

Build the ready-to-install bundle on an x86_64 Linux builder (use `rofl-13` or
`rofl-14`, not the phone):

```sh
nix build '.#termux-native-bundle'
sha256sum result/environment.tar.gz
```

Termux APT owns command line tools already in its repositories, including
`atuin`, `bat`, `eza`, `fd`, `gzip`, `ripgrep`, `tmux`, `udocker`, `unzip`,
`vivid`, and `zip`. APT resolves and tracks their dependencies. The bundle does
not copy or install `.deb` files or libraries from Termux packages. Reserve
Nix-built Android/Bionic outputs for supported tools Termux does not provide
and generated
configuration.

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
  Bionic for API 35. This makes the compiler target and runtime dependencies
  explicit. See [the NDK guide](https://developer.android.com/ndk/guides/other_build_systems).

A binary cache can store either output, including an entire assembled
environment. But it stores NAR objects and reference metadata, not a portable
installation transaction. Native Termux does not have `/nix/store`, and moving a
normal closure under `$HOME` does not rewrite its interpreters, RPATHs, symlinks,
or compiled-in file names. The [Nix store-path model](https://nix.dev/manual/nix/2.28/store/store-path)
explicitly distinguishes reference-free objects from objects tied to a store
directory.

Use the Nix cache between builders and release exporters. Export the payload
as a generation tarball for phones. Nix signatures do not
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

The first is the recommended starting point. Bundle supported Nix-built
Android/Bionic outputs and generated configuration; use Termux APT for packages
already provided by Termux, including their shared dependencies.

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
For this prototype the base is `bash`, `coreutils`, `tar`, and `zsh`. The first
archive extraction uses Android's `/system/bin/gzip` through GNU tar; the
installed generation then provides its own native Gzip commands. Production
also needs `curl`, CA certificates, and a signature verifier such as `minisign`.
Use `pkg install` for missing base packages. Android permissions,
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
- **Building Nixpkgs tools:** `native-binary.nix` selects the same package from
  Nixpkgs' Android cross set, then strips and exports its Android executable.
  It never repackages the ordinary Linux output: `patchelf` can remove Nix
  runtime paths, but cannot change glibc ABI into Bionic. The export stage also
  runs Termux's `termux-elf-cleaner` at the selected Android API level to remove
  ELF metadata unsupported by Bionic and repair TLS segment alignment. This is
  compatibility cleanup after compilation, not ABI conversion. For Go programs,
  `go-binary.nix` reuses the Nixpkgs package derivation and source while building
  with the host Go compiler for Android, then applies the Termux runtime-path
  and ELF cleanup. For Nixpkgs Android packages, the helper also records the
  target package's Nix runtime closure and target `buildInputs`. The exporter
  follows each executable's `DT_NEEDED` entries, copies matching Android
  libraries, recursively bundles their dependencies, and cleans their ELF
  metadata. Missing libraries and conflicting same-name candidates fail the
  build. Scripts, data files, and extra commands still need explicit package
  metadata. A package appearing in the cross set is not proof that its build
  works; build and inspect each selected output before exporting it.
  For example, Nixpkgs provides an Android cross derivation for `btop`, but its
  current build fails on Bionic pthread and C++ library gaps even with LTO and
  GPU support disabled. It is not included in the Termux bundle; making it work
  would need a maintained package-specific port.
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

## Zsh plugin manager boundary

The Termux Home Manager profile does not install or start Zinit. It imports the
shared Zsh settings and plugin modules, which source pinned plugin files from
the Nix generation. The regular yadm/Zinit startup remains in use on non-Termux
hosts. Termux startup also reuses selected yadm host and local configuration;
Nix overrides the prompt controls and update hooks that would otherwise call
the Zinit command. The compatibility function named `zinit::source-local-plugins`
only forwards to the Nix-managed local plugin loader; it does not load or
control Zinit.

This removes the Zinit scheduler and plugin-download phase from Termux shell
startup. The public `termux.sh` helper commands are exported as Termux shell
scripts by the Home Manager profile, without relying on Zinit's symlink-based
installer. ShellCheck is provided by Termux APT; the old upstream x86_64/proot
wrapper is not loaded by the native shell. The `zinit::source-local-plugins`
forwarder is still a compatibility seam for private yadm files and remains to
be removed when those call sites have native replacements.
Private yadm files remain runtime inputs from the phone's home directory and
are not copied into the public bundle.

The package adapter rebuilds a Nixpkgs recipe for Android/Bionic when
`pkgsCross.aarch64-android-prebuilt` provides a working derivation. It does not
repair an already-built glibc executable. `patchelf` only removes Nix-specific
ELF metadata as part of export; it cannot convert glibc ABI assumptions to
Bionic. Pure Go tools use a separate Android cross-build adapter. Both routes
need a real build and Termux runtime check for each selected package.

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
The flake exports `lib.mkTermuxBundle`, which accepts additional Home Manager
`modules` and `extraSpecialArgs` while retaining the standard Termux profile.

The profile splits packages by their runtime owner: entries in
`termux.packages` are installed by Termux APT, while Home Manager packages
with a `termuxNative` export declaration are built for Android/Bionic and
copied into the generated profile. It reuses the regular CLI modules and keeps
Linux hosts on their normal Nixpkgs packages. Termux APT supplies available
utilities and runtime-heavy packages, including Atuin, tmux, OpenSSL, ncurses,
libevent, libandroid-support, libandroid-glob, utf8proc, and their transitive
dependencies. APT tracks those files and owns their updates and removal; no
Termux `.deb` contents or libraries are copied into Nix generations. The
bundle is reserved for supported Nix-built
Android/Bionic artifacts and generated configuration. The Go toolchain is
patched to use Termux's `/etc` files so exported binaries do not refer to the
Nix store. Each exported ELF, including bundled libraries, is checked for
AArch64 ELF, an Android linker (or static linkage), and dependencies available
from Android system libraries or libraries bundled with that Nix-built
package. Dependencies of bundled libraries are checked recursively. The
profile also shares portable Neovim options and shell integrations from the
regular Home Manager tree.
The regular Linux LazyVim plugin closure is deliberately not included in the
Termux bundle.

The current installer trusts a digest obtained from the builder; it does not
verify a release signature or hostile archive contents. It keeps previous
generations for rollback but does not yet garbage-collect them, enforce an
anti-downgrade policy, or recover interrupted lock directories automatically.
APT package lifecycle is also install-only: bootstrap verifies the archive,
holds the activation lock, stages the generation, and runs its standalone
Android executable before asking APT to install the current manifest. Generation
activation then runs the shell smoke checks after APT has provided their
runtime dependencies and checks that required packages are installed. It
does not remove packages when a later generation stops declaring them, and it
does not record which packages were already installed before the first
bootstrap. A future removal path must preserve that pre-existing set and
remove only packages owned by this profile. Termux APT/dpkg should resolve
shared dependencies; nixpp must not remove a dependency while any selected
package still requires it. Generation rollback does not undo APT changes.
The bootstrap saves the existing `$PREFIX/etc/zshenv` and Termux login shell
before selecting the managed Zsh configuration. A cold app launch then starts
the managed shell directly. `bash bootstrap.sh restore` restores both saved
startup settings without removing installed generations.

## Verification record

The records below include historical experiments. The current profile leaves
Termux-provided packages and all their dependencies to APT.

On 2026-10-03, an earlier bundle prototype on the Zenfone 10's Termux app
installed official Termux packages `bat` 0.26.1, `fd` 10.5.0, `fzf` 0.74.4,
`grep` 3.12, `procps` 4.0.7, `ripgrep` 15.2.0, `sed` 4.10, `unzip` 6.0,
`zip` 3.0, and `zoxide` 0.10.0. Termux APT installed the selected packages;
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

On 2026-10-04, the latest native generation was cold-launched in the official
Termux app on both the Zenfone 10 and Mi Pad 4. The interactive Zsh smoke test
exercised shared widgets and prompt simple/reset controls, verified that neither
a Zinit manager nor command was present, and ran `assh`, `mani`, and `rancher`
from the active Android/Bionic generation. Both devices reported
`TERMUX_NATIVE_SMOKE_OK`.

The updated profile now imports the shared Atuin, direnv, fzf, vivid, and
zoxide Home Manager modules. They generate Termux-specific runtime hooks in
`system.zsh`; Linux continues to use its existing generated hooks. On both the
Zenfone 10 and Mi Pad 4, the app-driven install and PTY smoke test passed,
including the Atuin widget, direnv hook, zoxide functions, completions,
native tools, and the no-Zinit check. A cold app relaunch entered the managed
Zsh prompt. The active generation was
`deee8e89b5254466a5b5447c5a1eca729a533473d34a35489a70ef5ad0e0d452`.

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
Atuin was later briefly moved into the bundle, then restored to Termux APT as
described below.

An earlier bundle was built on rofl-13 with Nixpkgs' Android cross packages for
`ripgrep`, `fd`, and `bat`. Rust cross builds needed special handling to skip
emulator-based checks and target post-fixup commands, and the generation
launchers were verified on the Zenfone. These utilities now come from Termux
APT. The earlier generation digest was
`4b882492cc22e96a252e0efc4b82c1fef5599d522340e386b5eed4c4d118633a`.

An experimental Atuin bundle approach was retired. Atuin and its runtime
dependencies are installed and updated by Termux APT; its Home Manager
configuration and shell integration remain shared.

An earlier experiment bundled Nix-built Android/Bionic Zip, Unzip, and Gzip
commands. These tools now come from Termux APT, which also owns their
dependencies and updates.

On 2026-10-04, Android `ripgrep` was built with PCRE2 enabled. The exporter
automatically included `libpcre2-8.so` from the Nix Android runtime closure.
The 33 MiB bundle built on rofl-13, passed shell and Nix lint checks, and
activated through the Termux app on both the Mi Pad 4 and Zenfone 10. On both
devices, `rg -P '(?<=a)bc'` matched `abc`, and `rg --version` reported
`15.2.0`.

On 2026-10-04, a prototype bundle added Nix-built Android/Bionic Zip, Unzip,
and Gzip commands to the generation. The commands were smoke-tested on the
Zenfone. This experiment was superseded: these tools are available in Termux
APT and are now installed and tracked there.

A direct Nixpkgs Android cross-build of tmux failed in its Android dependency
graph before producing the package. A later experiment imported tmux and its
runtime libraries from pinned official Termux package artifacts; that adapter
is retired, and current Termux hosts install tmux and its dependencies through
APT. The shared Home Manager modules continue to generate its configuration
without changing Linux package selection.

The Termux APT tmux package was installed on the Zenfone 10 and verified by
creating, checking, and killing a detached session. Its Home Manager
configuration remains in the generated profile; the bundle does not include
tmux binaries or libraries.

On 2026-10-05, Termux APT became the owner of `bat`, `eza`, `fd`, `gzip`,
`ripgrep`, `unzip`, `vivid`, and `zip` as well as Atuin and tmux. The exporter
no longer builds or bundles those utilities. The 35 MiB bundle
`0ba4f15d04007df34a8ae21e97d779e95f45b1317e3ceff3e4247906a0f25015` was
built on rofl-13 and installed from the visible Termux app on both devices.
APT installed `fd` on each; on the Mi Pad it also updated gzip, certificates,
Atuin, diff-so-fancy, and tmux. Both bootstrap and interactive shell smoke
tests passed, including the no-Zinit check. After a force-stop and cold app
relaunch, both devices returned to the managed Zsh prompt. The generation
archive contains no copied Termux `.deb` files or APT-owned runtime libraries.
The activation probe now matches a complete CR-terminated numeric result and
closes each interactive PTY child once; it passed on both devices.

On 2026-10-06, `curl -L yadm.brkn.lol | bash -s -- --nixpp` completed in the
Zenfone's official Termux app. Both private archives passed integrity checks,
the Nix-built native executable ran, APT preparation completed, and the
managed generation's Zsh smoke checks passed. The initializer cloned yadm,
applied the `termux,notnixos` classes, and opened the managed Zsh prompt.

On 2026-10-05, the profile added `obs-cli` because Termux APT does not provide
it. The bundle ships its pure Python modules, including the explicit
`websocket-client` runtime dependency, and uses Termux APT's Python. Bundle
`b624b1723c6a2d141255922db7ca31758d36377f725dbd8df547fb04233aa679` built on
rofl-13 and activated through the visible Termux app on the Zenfone 10 and Mi
Pad 4. Bootstrap and smoke checks passed; APT made no package changes, and
after cold app relaunch `obs-cli --version` reported `0.9.5` on both devices.

A follow-up login-shell check found that Termux's login profile could put
`~/.local/bin/jc` ahead of the generated `jc`. Startup now reapplies package
precedence after the login profile, and every new shell resolves `current`
instead of inheriting a stale generation. Bundle
`8d6370bb04356b2ad85b97397dcff9de3ab840acc0e683bea5b5a6169a402e2d` passed
the login smoke check on the Zenfone 10 and Mi Pad 4. New shells on both also
selected the updated generation when started with a stale inherited value;
cold app relaunch returned to the managed prompt without plugin downloads.
