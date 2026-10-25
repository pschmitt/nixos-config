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

  # CI can fill the store between scheduled collections. Keep room for the
  # database, build logs, and incoming build inputs.
  nix.settings = {
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 40 * 1024 * 1024 * 1024;
  };

  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";
}
