{
  config,
  lib,
  pkgs,
  ...
}:
let
  pinchflatDomain = "pinchflat.${config.domains.main}";
  pinchflatPort = 28945;
  pinchflatUser = "pinchflat";
  pinchflatGroup = pinchflatUser;
  pinchflatMediaDir = "/mnt/data/srv/pinchflat/data";
  cookiesDir = "/srv/yt-dlp";
  pinchflatExtrasDir = "/var/lib/pinchflat/extras";
  autheliaConfig = import ./authelia-nginx-config.nix { inherit config; };
in
{
  sops.secrets."pinchflat/env" = {
    inherit (config.custom) sopsFile;
    owner = pinchflatUser;
    group = pinchflatGroup;
    mode = "0400";
    restartUnits = [ "pinchflat.service" ];
  };

  systemd.tmpfiles.rules = [
    "d ${pinchflatMediaDir} 0750 ${pinchflatUser} ${pinchflatGroup} -"
    "d ${cookiesDir} 0750 root ${pinchflatGroup} -"
    "d ${pinchflatExtrasDir} 0750 ${pinchflatUser} ${pinchflatGroup} -"
    "L+ ${pinchflatExtrasDir}/cookies.txt - - - - ${cookiesDir}/cookies.txt"
  ];

  services = {
    pinchflat = {
      enable = true;
      package = pkgs.pinchflat;
      user = pinchflatUser;
      group = pinchflatGroup;
      port = pinchflatPort;
      openFirewall = false;
      mediaDir = pinchflatMediaDir;
      secretsFile = config.sops.secrets."pinchflat/env".path;
      logLevel = "info";
      extraConfig = {
        YT_DLP_WORKER_CONCURRENCY = 2;
      };
    };

    nginx.virtualHosts."${pinchflatDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString pinchflatPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
      locations."~* (^/sources/[^/]+/feed(_image)?|^/media/[^/]+/(stream|episode_image))(\\.[a-zA-Z0-9]+)?$" =
        {
          proxyPass = "http://127.0.0.1:${toString pinchflatPort}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
    };

    monit.config = lib.mkAfter ''
      check host "pinchflat" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart pinchflat.service"
        if failed
          port ${toString pinchflatPort}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
