{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/server

    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/nfs/nfs-client-rofl-11.nix
    ../../services/tdarr-node.nix
    # ../../services/***REMOVED***/***REMOVED***.nix
    (import ../../services/***REMOVED***/***REMOVED***.nix {
      inherit config lib;
      useProxy = true;
      cpuUsage = 50;
    })

    # ../../services/github-runner.nix
  ];

  custom.cattle = true;
  custom.promptColor = "magenta";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
