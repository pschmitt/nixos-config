# Nix Configuration Tasks

## NIX-001: Migrate NetBox to the current bind option

Status: Complete

Replace removed `services.netbox.listenAddress`, `services.netbox.port`, and
`services.netbox.apiTokenPeppersFile` options. Keep nginx and Monit pointed at
the explicit loopback endpoint, then verify `rofl-10` evaluates.

## NIX-002: Retire or narrow legacy container-services

Status: Open

Audit `modules/container-services.nix` and the `rofl-10`/`rofl-11` registries.
Remove stale routes and monitoring entries, migrate Nix-managed containers to
their actual systemd units, and make any remaining Compose lifecycle explicit.

## NIX-003: Separate workstation composition from settings

Status: Open

Keep `profiles/workstation.nix` as a pure imports aggregator, moving shared
Home Manager, zram, Nix, and systemd tuning into an appropriately named module.
