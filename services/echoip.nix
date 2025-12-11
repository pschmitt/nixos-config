{ config, ... }:
{

  virtualisation.oci-containers.containers = {
    echoip = {
      image = "docker.io/createleafcloud/echoip";
      autoStart = true;
      ports = [ "127.0.0.1:18880:8080" ];
    };
  };

  services.nginx.virtualHosts = {
    "whoami.${config.networking.hostName}.${config.domains.main}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;

      locations."/".extraConfig = ''
        proxy_pass http://127.0.0.1:18880;
        proxy_set_header Host $host;
        proxy_redirect http:// https://;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
      '';
    };
  };
}
