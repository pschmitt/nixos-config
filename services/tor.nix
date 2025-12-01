{ lib, ... }:
{
  services.tor = {
    enable = true;
    openFirewall = false;
    settings = {
      ControlPort = 9051;
      CookieAuthentication = true;
      # NOTE Don't set the port here, it will add a secondary SocksPort option
      # in the torrc!
      # SocksPort = 9050;
    };
    relay.enable = false;
    client = {
      enable = true;
      dns.enable = true;
    };
    torsocks.enable = true;
    tsocks.enable = true;
  };

  programs.proxychains.proxies.torproxy.enable = lib.mkForce false;
}
