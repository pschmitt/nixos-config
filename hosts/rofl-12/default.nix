{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/server
    ../../common/global/users/home-assistant.nix

    (import ../../services/nfs/nfs-client.nix { })

    ../../services/http.nix
    ../../services/tor.nix

    ../../services/***REMOVED***/***REMOVED***-wallet-rpc.nix
    ../../services/***REMOVED***/***REMOVED***d.nix
    ../../services/***REMOVED***/***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-proxy.nix
    ../../services/***REMOVED***/***REMOVED***.nix
  ];

  hardware = {
    cattle = false;
    serverType = "openstack";
    biosBoot = lib.mkForce false;
  };
  custom.promptColor = "#ff6600";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  services = {
    ***REMOVED***.settings.cpu.max-threads-hint = lib.mkForce 15;

    ***REMOVED*** = {
      enable = true;
      inherit (config.custom) sopsFile;
      walletSecret = "***REMOVED***/wallet";
      mode = "mini"; # or "nano" for faster sync
      stratum.port = 13333; # 3333 is used by ***REMOVED***-proxy!
      openFirewall = true;
    };
  };
}
