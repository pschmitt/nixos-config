{ config, ... }:
{
  services.nginx = {
    virtualHosts =
      let
        commonConfig = {
          enableACME = true;
          # FIXME https://github.com/NixOS/nixpkgs/issues/210807
          acmeRoot = null;
          forceSSL = true;
          locations."/".extraConfig = ''
            proxy_pass http://127.0.0.1:8096;
            proxy_set_header Host $host;
            proxy_redirect http:// https://;
            # proxy_http_version 1.1;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
          '';
        };
      in
      {
        "jelly.${config.networking.hostName}.brkn.lol" = commonConfig;
        "jelly.${config.networking.hostName}.heimat.dev" = commonConfig;
        # legacy
        "jelly.rofl-01.heimat.dev" = commonConfig;
      };
  };
}
