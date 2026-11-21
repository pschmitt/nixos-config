{
  config,
  lib,
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
  stateDir = "/mnt/data/srv/audiobookshelf";
in
{
  systemd.tmpfiles.rules = [
    "d /mnt/data/audiobooks 2775 ${absUser} ${absGroup} - -"
    "Z /mnt/data/audiobooks 2775 ${absUser} ${absGroup} - -"
    "d ${stateDir} 0750 ${absUser} ${absGroup} - -"
  ];

  # The module only accepts a StateDirectory-relative dataDir. It is not
  # sandboxed and keeps config/ and metadata/ in its working directory, so
  # point that at the data disk (covered by the /mnt/data/srv restic backup)
  # and drop the now unused StateDirectory.
  systemd.services.audiobookshelf = {
    serviceConfig = {
      WorkingDirectory = lib.mkForce stateDir;
      StateDirectory = lib.mkForce [ ];
    };
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
  };

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
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString audiobookshelfPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.checks = {
      audiobookshelf = {
        type = "host";
        address = "127.0.0.1";
        group = "services";
        restartUnit = "audiobookshelf.service";
        conditions = ''
          if failed
            port ${toString audiobookshelfPort}
            protocol http
            with timeout 15 seconds
            for 3 cycles
          then restart
          if 3 restarts within 15 cycles then alert
        '';
      };
    };
  };
}
