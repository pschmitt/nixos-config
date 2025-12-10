{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8084;
  publicHost = "cwabd.arr.${config.domains.main}";
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
in
{
  virtualisation.oci-containers.containers.cwabd = {
    image = "ghcr.io/calibrain/calibre-web-automated-book-downloader";
    autoStart = true;
    environment = {
      FLASK_PORT = toString port;
      LOG_LEVEL = "info";
      BOOK_LANGUAGE = "en";
      USE_BOOK_TITLE = "true";
      TZ = "Europe/Berlin";
      APP_ENV = "prod";
      UID = "1000";
      GID = "100";
      MAX_CONCURRENT_DOWNLOADS = "3";
      DOWNLOAD_PROGRESS_UPDATE_INTERVAL = "5";
    };
    volumes = [
      "/mnt/data/books/ingest:/cwa-book-ingest"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];

  systemd.services."${config.virtualisation.oci-containers.containers.cwabd.serviceName}" = {
    after = [ "mullvad.service" ];
    requires = [ "mullvad.service" ];
  };

  services = {
    nginx.virtualHosts."${publicHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://${internalIP}:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "cwabd" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.containers.cwabd.serviceName}"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.cwabd.port = port;
}
