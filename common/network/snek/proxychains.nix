{ pkgs, ... }:

let
  mullvadHost = "10.64.0.1";
  mullvadPort = 1080;
  proxychainsMullvad = pkgs.writeShellApplication {
    name = "proxychains-mullvad";
    runtimeInputs = [ pkgs.proxychains-ng ];
    text = ''
      exec proxychains4 -f /etc/proxychains-mullvad.conf "$@"
    '';
  };
in
{
  programs.proxychains = {
    package = pkgs.proxychains-ng;
    enable = true;
    quietMode = false;
    proxyDNS = true;
    localnet = "127.0.0.0/255.0.0.0"; # TODO: nb+ts
    chain.type = "strict";
    proxies.mullvad = {
      enable = true;
      type = "socks5";
      host = mullvadHost;
      port = mullvadPort;
    };
  };

  environment.etc."proxychains-mullvad.conf".text = ''
    strict_chain
    proxy_dns
    remote_dns_subnet 224
    tcp_read_time_out 15000
    tcp_connect_time_out 8000

    [ProxyList]
    socks5 ${mullvadHost} ${toString mullvadPort}
  '';

  environment.systemPackages = [
    proxychainsMullvad
  ];
}
