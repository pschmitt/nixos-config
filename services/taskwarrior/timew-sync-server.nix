{
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/taskwarrior/data/timew";
  listenPort = 53590;
  runUser = "timew-sync-server";
in
{
  users.users.${runUser} = {
    isSystemUser = true;
    group = runUser;
  };
  users.groups.${runUser} = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${runUser} ${runUser} - -"
    "d ${dataDir}/authorized_keys 0750 ${runUser} ${runUser} - -"
    "Z ${dataDir} 0750 ${runUser} ${runUser} - -"
  ];

  systemd.services.timew-sync-server = {
    description = "Timewarrior sync server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = runUser;
      Group = runUser;
      DynamicUser = false;
      WorkingDirectory = dataDir;
      ExecStart = ''
        ${lib.getExe pkgs.timew-sync-server} start \
          --port ${toString listenPort} \
          --keys-location ${dataDir}/authorized_keys \
          --sqlite-db ${dataDir}/db.sqlite
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "timew-sync-server" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart timew-sync-server.service"
      if failed
        port ${toString listenPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
