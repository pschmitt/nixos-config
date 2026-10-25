# Keep the workstations' current main systems in fnuc's store so they
# substitute them over the LAN from fnuc's Harmonia (see the workstation
# profile's substituter priority) instead of fetching from S3 themselves.
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
    sourceHost = "nix-remote-builder@rofl-14.${config.domains.main}";
    sshKeyFile = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
    targets = map (host: "nixosConfigurations.${host}.config.system.build.toplevel") [
      "ge2"
      "gk4"
      "x13"
    ];
  };
}
