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

  # host = "0.0.0.0" plus openFirewall = false relies entirely on the
  # tailscale/netbird mesh being in networking.firewall.trustedInterfaces
  # (see profiles/features/network/{tailscale,netbird}.nix) -- this is a personal
  # sync server, never meant to be reachable from anywhere else. Make that
  # explicit instead of depending solely on listenPort never ending up in
  # allowedTCPPorts.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString listenPort} drop
  '';

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
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
  '';
}
