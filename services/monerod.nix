{ config, ... }:
{
  services.monero = {
    enable = true;
    rpc = {
      address = "127.0.0.1";
      port = 18081;
      # user = "fart";
      # password = "fart";
    };
    mining = {
      enable = false;
      threads = 0;
      address = "";
    };
  };
  services.nginx =
    let
      # TODO add a public endpoint, with basic auth?
      hostNames = [
        "rofl-06.nb.${config.custom.mainDomain}"
        "rofl-06.ts.${config.custom.mainDomain}"
      ];
      virtualHosts = builtins.listToAttrs (
        map (hostName: {
          name = hostName;
          value = {
            enableACME = true;
            # FIXME https://github.com/NixOS/nixpkgs/issues/210807
            acmeRoot = null;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://${config.services.monero.rpc.address}:${toString config.services.monero.rpc.port}";
              recommendedProxySettings = true;
              proxyWebsockets = true;
            };
          };
        }) hostNames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
