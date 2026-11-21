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
in
{
  # The module only accepts a StateDirectory-relative dataDir, so keep the
  # config/database on the data disk (covered by the /mnt/data/srv restic
  # backup) by bind-mounting it over the state directory.
  fileSystems."/var/lib/${config.services.audiobookshelf.dataDir}" = {
    device = "/mnt/data/srv/audiobookshelf";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/mnt/data"
    ];
  };

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
