---
name: nix
description: Use for system-level changes to NixOS hosts and Home Manager configurations. Handles Nix code updates, host deployments, and repository-wide Nix standards. Refer to AGENTS.md for foundational environment and deployment rules.
---

# Nix

Use this skill for system-level NixOS and Home Manager configuration tasks.

## Quick start

1.  **Foundational Rules**: Read and follow the core mandates in `AGENTS.md` before proceeding.
2.  **Repository Locations**:
    *   **NixOS**: `/etc/nixos`
    *   **Other OS**: `~/devel/private/pschmitt/nixos-config.git`
3.  **Scope**: This skill is specifically for modifications to host configurations, modules, and system/user profiles.

## Workflow

1.  **Strategic Research**: Identify the host or module requiring change within the `hosts/`, `modules/`, or `home-manager/` directories.
2.  **Compliance**: Ensure all changes adhere to the formatting (`nixfmt`) and linting (`statix`) requirements specified in `AGENTS.md`.
3.  **Deployment**: Follow the deployment procedure documented in `AGENTS.md` (using `just deploy`).

## Reference map

- `AGENTS.md`: Foundational repository guidelines, environment setup, and deployment commands.
- `references/conventions.md`: Detailed repository structure and Nix-specific conventions.

## Safety rules

- Ensure all Nix code is formatted before any verification step.
