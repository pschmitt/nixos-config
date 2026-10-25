# Keep the workstations' current main systems in fnuc's store so they
# substitute them over the LAN from fnuc's Harmonia (see the workstation
# profile's substituter priority) instead of fetching from S3 themselves.
{ config, ... }:
{
  imports = [ ../../services/harmonia-lan-mirror.nix ];

  services.harmonia.lanMirror = {
    enable = true;
    sourceHost = "nix-remote-builder@rofl-14.${config.domains.main}";
    sshKeyFile = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
    targets = map (host: "nixosConfigurations.${host}.config.system.build.toplevel") [
      "ge2"
      "gk4"
      "x13"
    ];
  };
}
