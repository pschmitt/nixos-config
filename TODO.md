# Nix Configuration Tasks

## NIX-001: Migrate NetBox to the current bind option

Status: Complete

Replace removed `services.netbox.listenAddress`, `services.netbox.port`, and
`services.netbox.apiTokenPeppersFile` options. Keep nginx and Monit pointed at
the explicit loopback endpoint, then verify `rofl-10` evaluates.

## NIX-002: Retire or narrow legacy container-services

Status: Complete

Audit `modules/container-services.nix` and the `rofl-10`/`rofl-11` registries.
Migrate Nix-managed containers to their actual systemd units, remove the
duplicate changedetection check, and make every external Compose lifecycle
explicit.

## NIX-003: Separate workstation composition from settings

Status: Open

Keep `profiles/workstation.nix` as a pure imports aggregator, moving shared
Home Manager, zram, Nix, and systemd tuning into an appropriately named module.
