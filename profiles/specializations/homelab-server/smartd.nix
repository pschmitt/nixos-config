{
  lib,
  pkgs,
  ...
}:
let
  checkSmartHealth = pkgs.writeShellApplication {
    name = "check-smart-health";
    runtimeInputs = [
      pkgs.jq
      pkgs.smartmontools
    ];
    text = builtins.readFile ./scripts/check-smart-health.sh;
  };
in
{
  services = {
    smartd = {
      enable = true;
      autodetect = true;
    };

    monit.checks = {
      smart-health = {
        type = "program";
        path = lib.getExe checkSmartHealth;
        group = "storage";
        every = 5;
        conditions = ''
          if status > 0 for 2 cycles then alert
        '';
      };

      smartd-daemon = {
        type = "process";
        matching = "smartd";
        group = "storage";
        restartUnit = "smartd.service";
        conditions = ''
          if not exist for 2 cycles then restart
        '';
      };
    };
  };
}
