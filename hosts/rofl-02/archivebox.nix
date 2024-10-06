{ config, lib, ... }:
let
  domains = [
    "brkn.lol"
    "heimat.dev"
  ];
  subdomains = [
    "arc"
    "archive"
    "archivebox"
  ];
  hostnames = lib.concatMap (
    domain:
    lib.concatMap (subdomain: [
      "${subdomain}.${domain}"
      "${subdomain}.${config.networking.hostName}.${domain}"
    ]) subdomains
  ) domains;
in
{
  services.nginx =
    let
      virtualHosts = builtins.listToAttrs (
        map (hostname: {
          name = hostname;
          value = {
            enableACME = true;
            # FIXME https://github.com/NixOS/nixpkgs/issues/210807
            acmeRoot = null;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:27244";
              proxyWebsockets = true;
              recommendedProxySettings = true;
            };
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
