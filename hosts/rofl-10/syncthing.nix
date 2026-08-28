{ config, ... }:

{
  imports = [ ../../profiles/syncthing.nix ];

  custom.syncthing = {
    documentsDir = "/mnt/data/srv/syncthing/documents";
    folders = {
      music = {
        label = "Music";
        dir = "/mnt/data/srv/syncthing/music";
      };
      pictures = {
        label = "Pictures";
        dir = "/mnt/data/srv/syncthing/pictures";
      };
      backups = {
        label = "Backups";
        dir = "/mnt/data/srv/syncthing/backups";
      };
    };
  };

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
