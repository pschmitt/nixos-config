{ lib, ... }:
{
  imports = [
    ../../features/network/roflnet.nix
    ../server
    ../tdarr-node

    ../../../services/browser-mcp-chromium-container.nix
    ../../../services/esphome.nix
    ../../../services/forgejo-runner.nix
  ];

  hardware = {
    cattle = true;
    serverType = "openstack";
  };

  nix.gc = {
    dates = lib.mkForce "daily";
    options = lib.mkForce "--delete-older-than 3d";
  };

  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    "/run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";
}
