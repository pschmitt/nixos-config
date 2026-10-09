{ config, lib, ... }:
{
  imports = [
    ../../features/network/roflnet.nix
    ../../headless-browsers.nix
    ../server

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
    "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";
}
