{ lib, pkgs, ... }:
{
  services.monit.config = lib.mkAfter ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert
  '';
}
