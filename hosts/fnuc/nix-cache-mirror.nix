# Keep the workstations' and lrz's current main systems in fnuc's store so they
# substitute them over the LAN from fnuc's Harmonia
# (profiles/features/network/fnuc-nix-cache.nix) instead of fetching from S3.
{ config, ... }:
let
  circus = "https://circus.rofl-15.${config.domains.netbird}";
in
{
  imports = [ ../../services/harmonia-lan-mirror.nix ];

  # / and /nix share one filesystem with the Home Assistant VM. Let Nix
  # collect unrooted store paths itself when free space runs low, instead of
  # waiting for the weekly nix-gc (replaced mirror outputs become unrooted).
  nix.settings = {
    min-free = 100 * 1024 * 1024 * 1024;
    max-free = 200 * 1024 * 1024 * 1024;
    extra-substituters = [ "${circus}/nix-cache/" ];
    extra-trusted-public-keys = [ "circus.brkn.lol-1:rib6EG6ItgQJbo9J+P5pNw6FK5UG9VzW0foZyhXlyeg=" ];
  };

  services.harmonia.lanMirror = {
    enable = true;
    # Above min-free, so the mirror never relies on emergency GC.
    minFreeGiB = 125;
    jobsetUrl = "${circus}/job/nixos-config/main";
    repository = "https://github.com/pschmitt/nixos-config.git";
    targets = map (host: "hosts.${host}") [
      "ge2"
      "gk4"
      "lrz"
      "x13"
    ];
  };
}
