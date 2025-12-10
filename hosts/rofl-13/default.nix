{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/server

    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/nfs/nfs-client-rofl-11.nix
    ../../services/tdarr-node.nix

    (import ../../services/xmr/xmrig.nix {
      inherit config lib;
      useProxy = true;
      cpuUsage = 50;
    })
  ];

  hardware.cattle = true;
  custom.promptColor = "yellow";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
