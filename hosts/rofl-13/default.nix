{ config, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix

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

  custom.cattle = true;
  custom.promptColor = "yellow";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
