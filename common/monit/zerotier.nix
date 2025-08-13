{
  lib,
  pkgs,
  ...
}:
let
  monitZeroTier = ''
    check network zerotier with interface ztbtosdaym
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart zerotier-one"
      if link down for 2 cycles then restart
      if 5 restarts within 10 cycles then alert
  '';

in
{
  services.monit.config = lib.mkAfter monitZeroTier;
}
