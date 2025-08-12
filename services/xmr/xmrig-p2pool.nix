{ config, ... }:
{
  services.xmrig.settings = {
    # NOTE This will put p2pool on the top of the list of pools!
    # xmrig does fallback, ie if p2pool is down, it will try the next pool.
    pools = [
      {
        url = "127.0.0.1:${toString config.services.p2pool.stratum.port}";
        user = "x"; # or "x+10000" for fixed diff
        pass = config.networking.hostName;
        keepalive = true;
        tls = false; # true only if p2pool has TLS certs
        "rig-id" = config.networking.hostName;
      }
    ];
  };
}
