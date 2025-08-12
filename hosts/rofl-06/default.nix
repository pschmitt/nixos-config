{ config, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs/nfs-client.nix { })

    ../../services/http.nix

    ../../services/xmr/xmrig.nix
    ../../services/xmr/monerod.nix
    ../../services/xmr/monero-wallet-rpc.nix
    ../../services/xmr/p2pool.nix
    ../../services/xmr/xmrig-p2pool.nix
    ../../services/xmr/xmrig-proxy.nix
  ];

  custom.cattle = true;
  custom.promptColor = "#ff6600";

  services.xmrig.settings.cpu.max-threads-hint = lib.mkForce 15;

  # Enable networking
  networking = {
    hostName = "rofl-06";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  services.monero.extraConfig = ''
    # add for p2pool's quick template updates
    zmq-pub=tcp://127.0.0.1:18083
  '';

  services.p2pool = {
    enable = true;
    walletSecret = "p2pool/wallet";
    sopsFile = config.custom.sopsFile;
    mode = "mini"; # or "nano" for faster sync
    stratum.port = 13333; # 3333 is used by xmrig-proxy!
    openFirewall = false;
    extraArgs = [
      # examples:
      # "--disable-upnp"
      # "--loglevel" "2"
    ];
  };
}
