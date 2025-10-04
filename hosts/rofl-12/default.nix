{ config, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs/nfs-client.nix { })

    ../../services/http.nix

    ../../services/xmr/monero-wallet-rpc.nix
    ../../services/xmr/monerod.nix
    ../../services/xmr/p2pool.nix
    ../../services/xmr/xmrig-p2pool.nix
    ../../services/xmr/xmrig-proxy.nix
    ../../services/xmr/xmrig.nix
  ];

  custom.cattle = false;
  custom.promptColor = "#ff6600";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  services = {
    xmrig.settings.cpu.max-threads-hint = lib.mkForce 15;

    monero.extraConfig = ''
      # add for p2pool's quick template updates
      zmq-pub=tcp://127.0.0.1:18083
    '';

    p2pool = {
      enable = true;
      walletSecret = "p2pool/wallet";
      sopsFile = config.custom.sopsFile;
      mode = "mini"; # or "nano" for faster sync
      stratum.port = 13333; # 3333 is used by xmrig-proxy!
      openFirewall = true;
      extraArgs = [
        # examples:
        # "--disable-upnp"
        # "--loglevel" "2"
      ];
    };
  };
}
