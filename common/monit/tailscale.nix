{
  lib,
  pkgs,
  ...
}:
let
  monitTailscale = ''
    check network tailscale with interface tailscale0
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart tailscaled"
      if link down for 2 cycles then restart
      if 5 restarts within 10 cycles then alert

    check host "tailscale magicdns" with address 100.100.100.100
      group "network"
      depends on "tailscale"
      restart program = "${pkgs.systemd}/bin/systemctl restart tailscaled"
      if failed ping for 2 cycles then restart
      if 3 restarts within 10 cycles then alert
  '';

in
{
  services.monit.config = lib.mkAfter monitTailscale;

  systemd.services.monit.after = [
    "tailscaled.service"
  ];
}
