# Keep the workstations' and lrz's current main systems in fnuc's store so they
# substitute them over the LAN from fnuc's Harmonia
# (profiles/features/network/fnuc-nix-cache.nix) instead of fetching from S3.
{ config, ... }:
{
  imports = [ ../../services/harmonia-lan-mirror.nix ];

  # / and /nix share one filesystem with the Home Assistant VM. Let Nix
  # collect unrooted store paths itself when free space runs low, instead of
  # waiting for the weekly nix-gc (replaced mirror outputs become unrooted).
  nix.settings = {
    min-free = 75 * 1024 * 1024 * 1024;
    max-free = 150 * 1024 * 1024 * 1024;
  };

  services.harmonia.lanMirror = {
    enable = true;
    # Above min-free, so the mirror never relies on emergency GC.
    minFreeGiB = 100;
    sourceUrl = "https://nixbot.${config.domains.main}/nix-outputs/github/pschmitt/nixos-config/main";
    targets = map (host: "herculesCI.onPush.default.outputs.hosts.${host}") [
      "ge2"
      "gk4"
      "lrz"
      "x13"
    ];
  };
}
