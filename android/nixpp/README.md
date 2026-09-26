# nixpp

`nixpp` is a small Termux-side reader for a deliberately narrow subset of
standard Nix binary caches. Nix on a trusted Linux builder produces the
Termux-compatible outputs; Termux fetches and verifies those outputs without
installing Nix or maintaining `/nix/store`.

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

## Build

The `nixpp-termux` package cross-compiles a Go AArch64 Android executable. It
uses Bionic through Android's `/system/bin/linker64` and has no Nix store
references. Build and test it on a Nix host, then exercise the binary on an
actual Termux device before relying on it:

```sh
CGO_ENABLED=0 go test ./...
nix build '.#nixpp-termux'
file result-nixpp-termux/bin/nixpp
readelf -l -d result-nixpp-termux/bin/nixpp
```

The client delegates HTTPS, DNS, and basic authentication to Termux's `curl`.
It uses the existing `xz` command for default Nix cache compression and Go's
standard gzip reader for gzip caches. The phone does not need Go or Nix.

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
