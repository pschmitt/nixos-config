{
  programs.proxychains = {
    enable = true;
    quietMode = false;
    proxyDNS = true;
    localnet = "127.0.0.0/255.0.0.0"; # TODO: nb+ts
    chain.type = "strict";
    proxies.mullvad = {
      enable = true;
      type = "socks5";
      host = "10.64.0.1";
      port = 1080;
    };
  };
}
