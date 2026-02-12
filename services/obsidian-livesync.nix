{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = "obsidian.${config.domains.main}";
  listenPort = 35984;
  dataDir = "/mnt/data/srv/obsidian-livesync";
  containerBackend = config.virtualisation.oci-containers.backend;
  systemdUnit = "${containerBackend}-obsidian-livesync";
in
{
  sops = {
    secrets = {
      "obsidian-livesync/username" = {
        inherit (config.custom) sopsFile;
      };
      "obsidian-livesync/password" = {
        inherit (config.custom) sopsFile;
      };
    };

    templates."obsidian-livesync/env" = {
      content = ''
        COUCHDB_USER=${config.sops.placeholder."obsidian-livesync/username"}
        COUCHDB_PASSWORD=${config.sops.placeholder."obsidian-livesync/password"}
      '';
      restartUnits = [ "${systemdUnit}.service" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.obsidian-livesync = {
    # renovate: datasource=docker depName=oleduc/docker-obsidian-livesync-couchdb
    image = "oleduc/docker-obsidian-livesync-couchdb:latest";
    autoStart = true;
    pull = "always";
    ports = [ "127.0.0.1:${toString listenPort}:5984" ];
    volumes = [ "${dataDir}:/opt/couchdb/data" ];
    environment = {
      SERVER_DOMAIN = host;
      PUID = "1000";
      PGID = "1000";
    };
    environmentFiles = [ config.sops.templates."obsidian-livesync/env".path ];
  };

  services.nginx.virtualHosts."${host}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "obsidian-livesync" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${systemdUnit}.service"
      if failed
        port ${toString listenPort}
        protocol http
        request "/"
        status 401
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
