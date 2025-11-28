{
  services.tor = {
    enable = true;
    openFirewall = false;
    settings = {
      ControlPort = [ { port = 9051; } ];
      CookieAuthentication = true;
      SocksPort = [ { port = 9050; } ];
    };
    relay.enable = false;
    client = {
      enable = true;
      dns.enable = true;
    };
    torsocks.enable = true;
    tsocks.enable = true;
  };
}
