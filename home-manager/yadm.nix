{ pkgs, ... }:
{
  systemd.user.services.yadm-pull = {
    Unit = {
      Description = "YADM Pull";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.yadm}/bin/yadm pull --autostash --ff-only --verbose";
    };

    Install = {
      WantedBy = [ ];
    };
  };

  systemd.user.timers.yadm-pull = {
    Unit = {
      Description = "YADM Pull";
    };

    Timer = {
      OnCalendar = "*-*-* 00/2:00:00";
      Persistent = true;
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
