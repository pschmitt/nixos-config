---
name: nix
description: Use for system-level changes to NixOS hosts and Home Manager configurations. Handles Nix code updates, host deployments, and repository-wide Nix standards. Refer to AGENTS.md for foundational environment and deployment rules.
---

# Nix

Use this skill for system-level NixOS and Home Manager configuration tasks.

## Hermes Agent

Work only in a repository checkout the user has made available in the Hermes
workspace. Do not assume `/etc/nixos`, `~/devel/private/...`, SSH deployment
access, or local SOPS/GPG keys exist. Ask for an available checkout or the
required capability before editing or deploying; the repository paths below are
for local Codex and shell workflows.

## Repository

- **NixOS hosts**: `/etc/nixos`
- **Other hosts**: `~/devel/private/pschmitt/nixos-config.git`
- **Git remote**: `https://github.com/pschmitt/nixos-config.git`

Read `AGENTS.md` in the repo root for environment setup, code style, and deployment rules.
See `references/conventions.md` for directory layout, secrets handling, and repo
idioms (no `with lib;`, `config.custom.mkSecret`, `writeShellApplication` + external
scripts, `common/` layers vs top-level `profiles/`, `pkgs.formats.*`, and how to
verify refactors).
