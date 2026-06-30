{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/global/users/home-assistant.nix

    (import ../../services/nfs/nfs-client.nix { })

    ../../services/http.nix
    ../../services/inet-proxy.nix
    ../../services/tor.nix

    ../../services/***REMOVED***/***REMOVED***-wallet-rpc.nix
    ../../services/***REMOVED***/***REMOVED***d.nix
    ../../services/***REMOVED***/***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-proxy.nix
    ../../services/***REMOVED***/ktunnel-***REMOVED***-proxy.nix
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
    inet-proxy = {
      enable = true;
      clusters = {
        cluster-02 = {
          enable = true;
          tunnelPort = 28700;
          lbPool = "edge-lb";
          nodePort = 30128;
        };
      };
    };

    ktunnel-***REMOVED***-proxy = {
      cluster-01 = {
        enable = true;
        tunnelPort = 28688;
      };
      cluster-02 = {
        enable = true;
        tunnelPort = 28689;
      };
    };

    ***REMOVED***.settings.cpu.max-threads-hint = lib.mkForce 15;

    ***REMOVED***-proxy.targetPool = "***REMOVED***";

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
