{ config, lib, ... }: {
  services.xmrig = {
    enable = true;
    settings = {
      autosave = true;
      opencl = false;
      cuda = false;
      cpu = {
        # https://xmrig.com/docs/miner/config/cpu
        enabled = true;
        priority = 1;
        # 25% of $nproc threads
        max-threads-hint = lib.mkDefault 25;
      };
      pools = [
        {
          url = "pool.hashvault.pro:443";
          # NOTE yes, this looks weird, and yes this works.
          user = ''''${HASHVAULT_USER}'';
          pass = config.networking.hostName;
          keepalive = true;
          tls = true;
        }
        {
          url = "xmrpool.eu:9999";
          # NOTE yes, this looks weird, and yes this works.
          user = ''''${XMRPOOL_USER}'';
          pass = config.networking.hostName;
          keepalive = true;
          tls = true;
        }
      ];
    };
  };

  age.secrets.wallets.file = ../secrets/wallets.age;

  systemd.services.xmrig.serviceConfig = {
    EnvironmentFile = config.age.secrets.wallets.path;
  };
}
