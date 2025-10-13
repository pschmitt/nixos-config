{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostnames = [
    "books.${config.custom.mainDomain}"
    "books.${config.networking.hostName}.${config.custom.mainDomain}"
  ];
  rootDir = "/mnt/data/srv/calibre";
  calibreLibrary = "${rootDir}/library";
  calibreWebListen = {
    ip = "127.0.0.1";
    port = 22543;
  };
  calibreServerListen = {
    ip = "127.0.0.1";
    port = 22542;
  };
  calibreWebUpstream = "http://${calibreWebListen.ip}:${toString calibreWebListen.port}";
  calibreServerUpstream = "http://${calibreServerListen.ip}:${toString calibreServerListen.port}";
in
{
  services.calibre-web = {
    enable = true;

    listen = calibreWebListen;

    dataDir = "${rootDir}/data";

    options = {
      calibreLibrary = calibreLibrary;
      enableBookConversion = true;
      enableBookUploading = true;
    };
  };

  services.calibre-server = {
    enable = true;
    host = calibreServerListen.ip;
    port = calibreServerListen.port;
    libraries = [ calibreLibrary ];
  };

  services.nginx.virtualHosts = builtins.listToAttrs (
    map (hostname: {
      name = hostname;
      value = {
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = calibreWebUpstream;
            recommendedProxySettings = true;
            proxyWebsockets = true;
          };

          # "/opds/" = {
          #   proxyPass = "${calibreServerUpstream}/";
          #   recommendedProxySettings = true;
          # };
        };
      };
    }) hostnames
  );

  services.monit.config = lib.mkAfter ''
    check host "calibre-web" with address "${builtins.head hostnames}"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart calibre-web.service"
      if failed
        port 443
        protocol https
        with timeout 15 seconds
        and certificate valid for 5 days
      then restart
      if 5 restarts within 10 cycles then alert

    # check host "calibre-server" with address "${builtins.head hostnames}"
    #   group services
    #   restart program = "${pkgs.systemd}/bin/systemctl restart calibre-server.service"
    #   if failed
    #     port 443
    #     protocol https
    #     request "/opds/"
    #     with timeout 15 seconds
    #     and certificate valid for 5 days
    #   then restart
    #   if 5 restarts within 10 cycles then alert
  '';
}
