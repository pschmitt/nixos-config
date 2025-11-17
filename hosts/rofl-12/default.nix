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
