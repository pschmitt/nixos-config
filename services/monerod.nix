{ config, ... }:
{
  # sops.secrets = {
  #   "monerod/htpasswd" = {
  #     owner = "nginx";
  #   };
  # };

  services.monero = {
    enable = true;
    extraConfig = ''
      # ref: https://docs.getmonero.org/interacting/monero-config-file/#monerodconf
      check-updates=disabled
      enable-dns-blocklist=1

      # Optional pruning
      prune-blockchain=1
      sync-pruned-blocks=1
    '';
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
        # public
        # "xmr.${config.custom.mainDomain}"
        # vpn
        "xmr.${config.networking.hostName}.nb.${config.custom.mainDomain}"
        "xmr.${config.networking.hostName}.ts.${config.custom.mainDomain}"
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
            # basicAuthFile = config.sops.secrets."monerod/htpasswd".path;
          };
        }) hostNames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
