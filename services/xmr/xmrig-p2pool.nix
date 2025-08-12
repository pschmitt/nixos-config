{ config, lib, ... }:

let
  common = {
    keepalive = true;
    pass = config.networking.hostName;
  };

  # p2pool first
  p2pool = common // {
    url = "127.0.0.1:${toString config.services.p2pool.stratum.port}";
    user = "x"; # or "x+<fixed-diff>"
    tls = false; # enable only if you gave p2pool TLS
    "rig-id" = config.networking.hostName;
  };

  publicPools = [
    (
      common
      // {
        url = "pool.hashvault.pro:443";
        user = "\${HASHVAULT_USER}";
        tls = true;
      }
    )
    (
      common
      // {
        url = "xmrpool.eu:9999";
        user = "\${XMRPOOL_USER}";
        tls = true;
      }
    )
  ];
in
{
  # We need to force this, because otherwise we would just append to the list
  # of pools and have duplicate entries.
  services.xmrig.settings.pools = lib.mkForce ([ p2pool ] ++ publicPools);
}
