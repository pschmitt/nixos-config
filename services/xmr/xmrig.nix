args@{ config, lib, ... }:
let
  useProxy = args.useProxy or false;
  cpuUsage = args.cpuUsage or 25;

  proxyPool = {
    url = "xmrig-proxy.rofl-12.${config.domains.netbirdDomain}:8443";
    user = config.networking.hostName;
    pass = "\${XMRIG_PROXY_PASSWORD}";
    keepalive = true;
    tls = true;
    nicehash = true;
    "rig-id" = config.networking.hostName;
  };

  publicPools = [
    {
      url = "pool.hashvault.pro:443";
      # NOTE yes, this looks weird, and yes this works.
      user = "\${HASHVAULT_USER}";
      pass = config.networking.hostName;
      keepalive = true;
      tls = true;
    }
    {
      url = "xmrpool.eu:9999";
      # NOTE yes, this looks weird, and yes this works.
      user = "\${XMRPOOL_USER}";
      pass = config.networking.hostName;
      keepalive = true;
      tls = true;
    }
  ];

  pools = if useProxy then [ proxyPool ] else publicPools;
in
{
  sops.secrets."xmrig/env" = {
    restartUnits = [ "xmrig.service" ];
  };
  systemd.services.xmrig.serviceConfig = {
    EnvironmentFile = config.sops.secrets."xmrig/env".path;
  };

  services.xmrig = {
    enable = true;
    settings = {
      inherit pools;

      autosave = true;
      opencl = false;
      cuda = false;
      cpu = {
        # https://xmrig.com/docs/miner/config/cpu
        enabled = true;
        priority = 1;
        # Configurable percentage of $nproc threads
        max-threads-hint = lib.mkDefault cpuUsage;
      };
      # https://xmrig.com/docs/miner/hugepages
      randomx = {
        "1gb-pages" = true;
      };
    };
  };
}
