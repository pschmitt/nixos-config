{
  services.monit.checks = {
    tailscale = {
      type = "network";
      interface = "tailscale0";
      group = [
        "network"
        "tailscale"
      ];
      restartUnit = "tailscaled";
      conditions = ''
        if link down for 2 cycles then restart
        if 5 restarts within 10 cycles then alert
      '';
    };

    "tailscale magicdns" = {
      type = "host";
      address = "100.100.100.100";
      group = [
        "network"
        "tailscale"
      ];
      dependsOn = [ "tailscale" ];
      restartUnit = "tailscaled";
      conditions = ''
        if failed ping for 2 cycles then restart
        if 3 restarts within 10 cycles then alert
      '';
    };
  };

  systemd.services.monit.after = [
    "tailscaled.service"
  ];
}
