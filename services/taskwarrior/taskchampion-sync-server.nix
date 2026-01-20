{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/taskwarrior/data/taskchampion-sync-server";
  listenPort = 53591;
in
{
  services.taskchampion-sync-server = {
    enable = true;
    host = "0.0.0.0";
    port = listenPort;
    inherit dataDir;
    openFirewall = false;
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${config.services.taskchampion-sync-server.user} ${config.services.taskchampion-sync-server.group} - -"
    "Z ${dataDir} 0750 ${config.services.taskchampion-sync-server.user} ${config.services.taskchampion-sync-server.group} - -"
  ];

  services.monit.config = lib.mkAfter ''
    check host "taskchampion-sync-server" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart taskchampion-sync-server.service"
      if failed
        port ${toString listenPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
