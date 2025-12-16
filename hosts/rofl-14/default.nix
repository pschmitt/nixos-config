{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/server

    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/nfs/nfs-client-rofl-11.nix
    ../../services/tdarr-node.nix
    # ../../services/xmr/xmrig.nix
    (import ../../services/xmr/xmrig.nix {
      inherit config lib;
      useProxy = true;
      cpuUsage = 50;
    })

    # ../../services/github-runner.nix
  ];

  hardware.cattle = true;
  hardware.serverType = "openstack";
  custom.promptColor = "magenta";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
