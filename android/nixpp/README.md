# nixpp

`nixpp` is a small Termux-side client for reference-free Nix outputs. A trusted
Linux host evaluates and builds Termux-compatible outputs; Termux verifies and
installs them without running Nix or maintaining `/nix/store`.

The initial supported contract is intentionally small:

- outputs are signed by a trusted Nix cache Ed25519 key;
- the requested store path has no Nix references;
- cache NAR compression is `none`, `gzip`, or `xz` (`xz-utils` is already in
  the Termux prefix used by this bootstrap);
- the output is unpacked into a new directory, which is atomically renamed into
  place only after signature, size, hash, and archive checks pass;
- NAR paths and symlinks cannot escape the destination.

This is not a general Nix package manager. It does not evaluate derivations,
build packages, traverse store closures, relocate `/nix/store` references, or
install arbitrary Linux/glibc outputs. Package derivations must produce Bionic
compatible files and prove `allowedReferences = []` before they are published.
Home Manager modules run on the trusted builder; their Termux-ready files are
assembled into a reference-free output for `nixpp` to fetch. The client itself
does not interpret Home Manager options or run Home Manager activation.

## Build

The `nixpp-termux` package cross-compiles the Rust CLI for AArch64 Android. It
uses Bionic through Android's `/system/bin/linker64` and has no Nix store
references. Fenix supplies the Rust Android standard library, while the NDK
provides the target linker. Cargo dependencies and versions are pinned in
`Cargo.lock`. Run the native unit suite on a Nix host, then build and exercise
the Android binary on a Termux device:

```sh
cargo test --locked --manifest-path android/nixpp/Cargo.toml
nix build '.#nixpp-termux'
file result-nixpp-termux/bin/nixpp
readelf -l -d result-nixpp-termux/bin/nixpp
```

The `fetch` command delegates HTTPS, DNS, and basic authentication to Termux's
`curl`; Rust verifies Nix cache signatures and hashes before extracting the
NAR. Termux's `gzip` and `xz` commands decompress those supported cache formats.
The phone does not need Rust, Cargo, or Nix.

## Build and switch from Termux

`switch` asks an SSH builder to evaluate and build a flake installable, then
streams that one output back to the phone. The remote build accepts the
requested flake's `nixConfig`, allowing its configured binary caches to be
used. Termux packages are installed and tracked by Termux APT; Android/Bionic
packages explicitly declared in `home.packages` are built and transferred by
nixpp. The builder exports the output to a
temporary local Nix cache, where Nix signs it with the builder's configured
`secret-key-files`. nixpp verifies the NAR signature and hash, rejects store
references, checks the bundle archive digest, then runs the bundle's
`bootstrap.sh`. The bootstrap installs required Termux APT packages, health
checks the new generation, and atomically selects it.

The switch command labels each build, verification, transfer, and activation
phase and reports how long each took. It uses color on an interactive terminal;
set `NO_COLOR` to disable ANSI color.

```sh
export NIXPP_PUBLIC_KEY='builder-cache-key:BASE64_PUBLIC_KEY'
nixpp switch \
  --flake 'path:/path/on/builder/to/flake#termuxBundle' \
  --builder rofl-13
```

`--public-key` can be used instead of `NIXPP_PUBLIC_KEY`. The builder needs
Nix, a configured signing key, and SSH access from Termux. Termux must already
trust the builder's SSH host key and have an SSH key authorized there. The
flake installable must produce exactly one reference-free directory containing
`environment.tar.gz`, `SHA256SUMS`, and `bootstrap.sh`, as the root flake's
`.#termux-native-bundle` output does. The archive is verified before the
existing generation installer receives it. Each invocation builds and
activates the selected flake output; the previous generation remains available
for rollback through its `activate.sh`.

`switch` streams the signed NAR over SSH and does not publish it to an HTTP
cache. Use `fetch` for outputs already published to a standard Nix binary
cache.

The flake also exposes `termux-prefix-cache` and `termux-home-cache`. The
builder first prepares the Termux `$PREFIX` and Zinit/tool home cache on
`rofl-13`, then Nix wraps each archive as its own reference-free output. The
publisher signs those Nix outputs into the private binary cache. The phone
fetches the two outputs separately, verifies them with the cache public key,
and unpacks their archives. This makes each published payload addressable as a
real Nix store path without requiring Nix or `/nix/store` on Termux.

## Fetch one output

The requested full store path identifies one output in the cache. Pass the
bootstrap's private netrc file rather than putting credentials in command
arguments or child process environments:

```sh
  nixpp fetch \
    --cache https://blobs.brkn.lol/private/termux/cache \
    --store-path /nix/store/STOREHASH-termux-zinit-cache \
    --destination "$HOME/.cache/nixpp/termux-zinit-cache" \
    --netrc-file "$HOME/.cache/termux-netrc" \
    --public-key 'cache-key-name:BASE64_PUBLIC_KEY'
```

The cache path and public key are public configuration. The password must come
from the existing Bitwarden-backed bootstrap flow. A signed channel index can
later map stable names such as `bootstrap` and `zinit-cache` to store paths;
this prototype currently expects the store path explicitly.

## Verification

The first client prototype was built on `rofl-13` and exercised through the
Termux app on the Zenfone 10 against a signed Nix file cache. It verified the
cache signature, compressed-file hash, NAR hash and size, extracted the output,
and ran the extracted binary on-device.

The full private-cache flow now publishes three reference-free Nix outputs:
the `nixpp` client, the Termux package prefix, and the Zinit/tool home cache.
`yadm-init` downloads the first-stage client and channel manifest from the
authenticated private blob directory, then uses the client to fetch and verify
the prefix and home outputs from the signed Nix cache. This flow has been run
through the Termux app on a Zenfone 10 after clearing Termux app data. The
client verified cache signatures, NAR hashes and sizes,
and extracted both outputs; the resulting shell reported the expected Termux
yadm classes and `uv tool list` showed the preinstalled `linkding-cli` tool.
Closing and relaunching the app did not trigger Zinit plugin fetches.

An earlier prototype run on 2026-10-03 used a builder-local Termux `.deb`
directory to install `zoxide` through Termux APT. That builder-path
integration has been removed. The current profile keeps Termux system packages
under APT where they need Termux's patched runtime, and exports supported
Home Manager packages as Android/Bionic binaries. Rust cross builds currently
provide `bat`, `eza`, `fd`, `ripgrep`, `vivid`, and `zoxide`; host-Go builds
provide `direnv`, `eget`, and `fzf`. The Rust `nixpp` client is cross-built
for Android/Bionic. Atuin and tmux are
imported from pinned Termux package artifacts with their runtime libraries,
removing them from the APT install set. Neovim remains a Termux APT package.
The shared `home-manager/cli/eget.nix` module selects the normal Nixpkgs
package on Linux and the Android binary in the Termux profile. Exported files are checked for
Android ELF format and Nix store references. The Android cross toolchain runs
on the trusted Nix builder; nixpp transfers the resulting reference-free
profile bundle.

Nixpkgs exposes Android cross packages for more programs than this list, but
that does not mean their Android dependency graph builds. In the pinned
Nixpkgs revision, cross-building Neovim and Atuin currently fails in dependency
builds (`attr` calls missing Bionic `IFTODT`; OpenSSL fails on Bionic socket
types). Neovim remains a Termux APT package; Atuin uses the Termux package
artifact in the bundle instead.

## First-stage bootstrap

`nixpp` cannot fetch itself on an empty Termux install. The curl-piped yadm-init
entrypoint therefore downloads the small AArch64 client and its checksum from
the authenticated private blob directory, then uses it for the signed Nix
outputs. Stable links select the current immutable client and channel manifest;
the manifest carries the client, prefix, and home store paths. The client
checksum currently relies on the authenticated HTTPS blob endpoint, while the
large prefix and home payloads are authenticated by Nix cache signatures. The
latest cold app-driven run took about 11 minutes from entering the curl-piped
provisioner, after the official Termux app's first-run setup, to the configured
Zsh prompt. It excludes installing and opening the Termux app and its initial
package setup.

Do not put private dotfiles or credentials in public outputs or publish their
source paths to a public cache. Cache outputs intended for Termux must be
audited separately from builder inputs; `allowedReferences = []` prevents
store references but is not a content or secrecy audit.
