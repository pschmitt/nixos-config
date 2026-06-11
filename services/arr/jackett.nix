{ config, ... }:
{
  arr.services.jackett = {
    port = 9117;
    host = "jackett.arr.${config.domains.main}";
    # Jackett has no lightweight health endpoint; probe the TCP port only.
    monit.request = null;
  };

  services.jackett.enable = true;
}
