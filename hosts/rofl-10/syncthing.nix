{ config, ... }:

{
  imports = [ ../../common/syncthing-devices.nix ];

  custom.syncthing.enable = true;

  services.nginx.virtualHosts."sync.${config.domains.main}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    basicAuthFile = config.sops.secrets."htpasswd".path;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8384";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
