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

    ../../services/xmr/monero-wallet-rpc.nix
    ../../services/xmr/monerod.nix
    ../../services/xmr/p2pool.nix
    ../../services/xmr/xmrig-p2pool.nix
    ../../services/xmr/xmrig-proxy.nix
    ../../services/xmr/ktunnel-xmrig-proxy.nix
    ../../services/xmr/xmrig.nix
    ../../services/monit/ktunnel.nix
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

    ktunnel-xmrig-proxy = {
      cluster-01 = {
        enable = true;
        tunnelPort = 28688;
      };
      cluster-02 = {
        enable = true;
        tunnelPort = 28689;
      };
    };

    xmrig.settings.cpu.max-threads-hint = lib.mkForce 15;

    xmrig-proxy.targetPool = "p2pool";

    p2pool = {
      enable = true;
      inherit (config.custom) sopsFile;
      walletSecret = "p2pool/wallet";
      # Dedicated subaddress (labelled "p2pool" in the wallet) so payouts can
      # be told apart from other incoming transfers to the primary address.
      subaddressSecret = "p2pool/subaddress";
      mode = "mini"; # or "nano" for faster sync
      stratum.port = 13333; # 3333 is used by xmrig-proxy!
      openFirewall = true;
    };
  };
}
