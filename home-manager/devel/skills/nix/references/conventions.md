# Nix Conventions

## Repository Structure

- `hosts/`: Per-host NixOS configurations.
- `modules/`: Shared NixOS modules.
- `home-manager/`: User-level Home Manager configurations.
- `common/`: Shared configuration snippets.
- `pkgs/`: Custom package definitions.
- `overlays/`: Nixpkgs overlays.
- `hardware/`: Hardware-specific configuration snippets.

## Secrets

Secrets are managed using SOPS.
- Configuration: `.sops.yaml`
- Secrets directory: `secrets/`
- Tool: `sops`

Avoid printing decrypted secrets to the console or logs.
