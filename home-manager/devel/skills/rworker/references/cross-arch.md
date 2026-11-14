# Cross-arch (aarch64) builds

The worker image registers `aarch64-linux` through qemu-user, so a worker can
build for the aarch64 hosts (for example `nixosConfigurations.oci-01`).
Workers created from an older image fail with `platform mismatch`; check
with `nix eval --raw 'nixpkgs#system'`-style probes or just try a build.

Emulation is several times slower than a native build. Use it only for
closures that no cache holds, then `niks3 push` the result so the target
substitutes it (see [host-closures](host-closures.md)).
