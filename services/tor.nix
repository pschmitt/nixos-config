{ lib, pkgs, ... }:

let
  proxychainsTor = pkgs.writeShellApplication {
    name = "proxychains-tor";
    runtimeInputs = [ pkgs.proxychains ];
    text = ''
      exec proxychains4 -f /etc/proxychains-tor.conf "$@"
    '';
  };
in
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

  environment.etc."proxychains-tor.conf".text = ''
    strict_chain
    proxy_dns
    remote_dns_subnet 224
    tcp_read_time_out 15000
    tcp_connect_time_out 8000

    [ProxyList]
    socks5 127.0.0.1 9050
  '';

  environment.systemPackages = [
    proxychainsTor
  ];
}
