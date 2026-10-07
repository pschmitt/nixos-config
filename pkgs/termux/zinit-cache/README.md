# Termux bootstrap and home cache

The package exposed as `nix run '.#termux-zinit-cache' -- SOURCE_ROOT
OUTPUT_DIR` builds an APT-based Termux prefix archive and a separate zinit/TPM
home cache. It requires Docker and the NixOS AArch64 binfmt handler when
building the AArch64 Termux image from an x86_64 host. The private configuration
repository contains the host-specific build and publish command.

The command archives only the committed zsh tree, tmux tree, the pinned TPM
submodule, and Termux package list from yadm. It excludes the secret zsh file
and host-specific zsh files; the snapshot is staged temporarily and removed
after the build. No yadm files are copied into this repository or a Nix
derivation. The build installs the declared Termux package list plus the
packages required to prewarm zinit and TPM before producing the prefix image.

`SOURCE_ROOT` is a private yadm snapshot with only the inputs needed by the
build. Set `YADM_ZSH_TREE`, `YADM_TMUX_TREE`, and
`YADM_TERMUX_PACKAGES_BLOB` to their Git object IDs. The source is staged in a
temporary directory, mounted read-only into the Termux container, and excluded
from the Nix derivation and Docker image. The output archive is checked to
contain only `share/`, `bin/`, and `lib/` cache files; ELF executables and
libraries under `bin/` and `lib/` must be AArch64. The builder suppresses
plugin logs so private config text cannot be copied into public build logs.

The output directory contains `termux-prefix.tar.gz` (the full `usr/` tree and
dpkg database), `termux-home.tar.gz` (only `.local/{bin,lib,share}`), SHA-256
files, and a build manifest. The prefix and home archives are validated to
contain only their expected top-level paths. The publisher gives both archives
immutable names and updates one latest manifest only after both files and
checksums are in place.
The builder removes its generated OpenSSH host keys and leaves `sshd` and
`ssh-agent` disabled; the device initializer creates fresh host keys for each
Termux installation.
