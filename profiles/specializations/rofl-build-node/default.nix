{ config, lib, ... }:
{
  imports = [
    ../../features/network/roflnet.nix
    ../../../services/headless-browsers/browser-daemon.nix
    ../server

    ../../../services/esphome.nix
    ../../../services/forgejo-runner.nix
    # Serve the store, so other hosts substitute what nixbot built here.
    ../../../services/harmonia.nix
  ];

  hardware = {
    cattle = true;
    serverType = "openstack";
  };

  # Placement label for browser-daemon: cloud-hosted nodes (profiles can be
  # placed on, or moved to, "cloud" nodes).
  services.browser-daemon.nodeGroups = [ "cloud" ];

  nix.gc = {
    dates = lib.mkForce "daily";
    options = lib.mkForce "--delete-older-than 3d";
  };

  # Keep the shared build directory from accumulating abandoned work trees.
  systemd.tmpfiles.rules = [
    "e /home/${config.mainUser.username}/build - - - 3d"
    # Interrupted builds leave their scratch behind and Nix never removes it.
    # Boot only (!): nothing is building yet.
    "R! /nix/var/nix/builds/nix-*"
  ];

  # Last resort against a full disk; the scheduled collection does the regular
  # work. Every daemon worker below min-free runs its own full collection and
  # they queue on one lock, so a node that sits below it with little garbage
  # stalls every build and evaluation for hours.
  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 15 * 1024 * 1024 * 1024;
  };

  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";
}
