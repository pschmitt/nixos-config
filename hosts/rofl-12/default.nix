{ config, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./restic.nix

    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs/nfs-client.nix { })

    ../../services/http.nix

    ../../services/***REMOVED***/***REMOVED***-wallet-rpc.nix
    ../../services/***REMOVED***/***REMOVED***d.nix
    ../../services/***REMOVED***/***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-***REMOVED***.nix
    ../../services/***REMOVED***/***REMOVED***-proxy.nix
    ../../services/***REMOVED***/***REMOVED***.nix
  ];

  custom.cattle = false;
  custom.promptColor = "#ff6600";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  services = {
    ***REMOVED***.settings.cpu.max-threads-hint = lib.mkForce 15;

    ***REMOVED***.extraConfig = ''
      # add for ***REMOVED***'s quick template updates
      zmq-pub=tcp://127.0.0.1:18083
    '';

    ***REMOVED*** = {
      enable = true;
      walletSecret = "***REMOVED***/wallet";
      sopsFile = config.custom.sopsFile;
      mode = "mini"; # or "nano" for faster sync
      stratum.port = 13333; # 3333 is used by ***REMOVED***-proxy!
      openFirewall = true;
      extraArgs = [
        # examples:
        # "--disable-upnp"
        # "--loglevel" "2"
      ];
    };
  };
}
