# Termux zsh and tmux cache

The package exposed as `nix run '.#termux-zinit-cache' -- SOURCE_ROOT
OUTPUT_DIR` builds an APT-based Termux zinit and TPM plugin cache. It requires
Docker and the NixOS AArch64 binfmt handler when building the AArch64 Termux
image from an x86_64 host. The private configuration repository contains the
host-specific build and publish command.

The command archives only the committed zsh tree, tmux tree, the pinned TPM
submodule, and Termux package list from yadm. It excludes the secret zsh file
and host-specific zsh files; the snapshot is staged temporarily and removed
after the build. No yadm files are copied into this repository or a Nix
derivation.

`SOURCE_ROOT` is a private yadm snapshot with only the inputs needed by the
build. Set `YADM_ZSH_TREE`, `YADM_TMUX_TREE`, and
`YADM_TERMUX_PACKAGES_BLOB` to their Git object IDs. The source is staged in a
temporary directory, mounted read-only into the Termux container, and excluded
from the Nix derivation and Docker image. The output archive is checked to
contain only `share/`, `bin/`, and `lib/` cache files; ELF executables and
libraries under `bin/` and `lib/` must be AArch64. The builder suppresses
plugin logs so private config text cannot be copied into public build logs.

The output directory contains `zinit-cache.tar.gz`, its SHA-256 file, and a
manifest. The publisher gives the archive an immutable name and updates a
latest manifest after the archive and checksum are in place.
