{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/network/roflnet.nix
    ../../profiles/tdarr-node.nix
    ../../services/esphome.nix
    ../../services/browser-mcp-chromium-container.nix
  ];

  hardware = {
    cattle = true;
    serverType = "openstack";
  };
  custom.promptColor = "yellow";
  nixHost.extraSubstituters = [
    "https://cache.rofl-10.brkn.lol"
    "https://cache.rofl-14.brkn.lol"
  ];

  # Keep the build/cache host from retaining weeks of obsolete outputs while
  # preserving the five newest NixOS system generations for rollback.
  nix.gc = {
    dates = lib.mkForce "daily";
    options = lib.mkForce "--delete-older-than 3d";
  };
  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    "/run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
