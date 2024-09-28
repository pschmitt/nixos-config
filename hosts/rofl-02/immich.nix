{ config, lib, ... }:
let
  domains = [
    "brkn.lol"
    "heimat.dev"
  ];
  subdomains = [
    "img"
    "immich"
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
  services.immich = {
    enable = true;
    # NOTE listening on "localhost" leads to immich only listening on IPv6
    host = "127.0.0.1";
    port = 3001;
    mediaLocation = "/mnt/data/srv/immich/media";
  };

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
            locations."/".extraConfig = ''
              proxy_pass http://127.0.0.1:${toString config.services.immich.port};
              proxy_set_header Host $host;
              proxy_redirect http:// https://;
              # proxy_http_version 1.1;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
            '';
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
