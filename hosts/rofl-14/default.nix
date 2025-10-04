{ lib, ... }:
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
    ../../services/xmr/xmrig.nix

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
