---
name: nix
description: Use for NixOS and Home Manager configuration tasks. Directs agents to the nixos-config repositories and their AGENTS.md guidelines.
---

# Nix

Use this skill for NixOS and Home Manager configuration tasks.

Before making changes or running deployments, read `AGENTS.md` in the root of the relevant repository for environment setup, deployment workflows, code style, repository layout, and conventions.

## Repositories

### nixos-config (Public)

Main NixOS and Home Manager system configuration repository.

- **Local path**:
  - `~/devel/private/pschmitt/nixos-config.git`
- **Git URLs**:
  - `git@github.com:pschmitt/nixos-config.git`
  - `https://github.com/pschmitt/nixos-config.git`
- **Guidelines**: Read `AGENTS.md` in the repository root.

### nixos-config-private (Private)

Private counterpart repository containing SOPS secrets, private host configurations, OpenTofu infrastructure, and private services.

- **Local path**:
  - `~/devel/private/pschmitt/nixos-config-private.git`
- **Git URLs**:
  - `git@github.com:pschmitt/nixos-config-private.git`
  - `https://github.com/pschmitt/nixos-config-private.git`
- **Guidelines**: Read `AGENTS.md` in the repository root.
