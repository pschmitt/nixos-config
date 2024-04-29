{ lib, pkgs, ... }:
let

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

    check program "docker compose services" with path "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk status"
      depends on "dockerd"
      group docker
      start program = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d" with timeout 300 seconds
      every 2 cycles
      if status > 0 then start
      if 3 restarts within 10 cycles then unmonitor
  '';
in
{
  services.monit.config = lib.mkAfter monitExtraConfig;
}
