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
    "books.${mainDomain}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;

  audiobookshelfPort = 8000;
  absUser = config.services.audiobookshelf.user;
  absGroup = config.users.users.${absUser}.group;
in
{
  systemd.tmpfiles.rules = [
    "d /mnt/data/audiobooks 2775 ${absUser} ${absGroup} - -"
    "Z /mnt/data/audiobooks 2775 ${absUser} ${absGroup} - -"
  ];

  users.users.${config.mainUser.username}.extraGroups = [ absGroup ];

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
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };
}
