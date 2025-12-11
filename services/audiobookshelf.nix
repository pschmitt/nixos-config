{
  config,
  lib,
  pkgs,
  ...
}:
let
  mainDomain = config.domains.main;
  hostnames = [
    "abs.${mainDomain}"
    "audiobookshelf.${mainDomain}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;

  audiobookshelfPort = 8000;
in
{
  services = {
    audiobookshelf = {
      enable = true;
      host = "127.0.0.1";
      port = audiobookshelfPort;
    };

    nginx.virtualHosts."${primaryHost}" = {
      inherit serverAliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString audiobookshelfPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "audiobookshelf" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart audiobookshelf.service"
        if failed
          port ${toString audiobookshelfPort}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
