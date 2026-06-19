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

    p2pool = {
      enable = true;
      inherit (config.custom) sopsFile;
      walletSecret = "p2pool/wallet";
      mode = "mini"; # or "nano" for faster sync
      stratum.port = 13333; # 3333 is used by xmrig-proxy!
      openFirewall = true;
    };
  };
}
