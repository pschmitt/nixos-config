# Nix Conventions

## Repository Structure

Refer to these directories when making system-level changes:
- `hosts/`: Per-host NixOS configurations.
- `modules/`: Shared NixOS modules.
- `home-manager/`: User-level Home Manager configurations.
- `common/`: Shared configuration snippets.
- `pkgs/`: Custom package definitions.
- `overlays/`: Nixpkgs overlays.
- `hardware/`: Hardware-specific configuration snippets.

## Location

The authoritative repository is always `~/devel/private/pschmitt/nixos-config.git`,
regardless of the host OS. `/etc/nixos` is not used.

## Standards & Deployment

**Foundation**: All formatting (`nixfmt`), linting (`statix`), and deployment (`just deploy`) rules are defined in `AGENTS.md`. 

### Key Command Patterns

- **Flake Selectors**: Always use single quotes (e.g., `nix build '.#fnuc'`).
- **Dev Shell**: Use `nix develop` to access required tooling.

## Secrets

Secrets are managed using SOPS.
- Configuration: `.sops.yaml`
- Secrets directory: `secrets/`
- Tool: `sops`

Avoid printing decrypted secrets to the console or logs.
