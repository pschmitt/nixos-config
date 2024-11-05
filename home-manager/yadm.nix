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
      WantedBy = [ "default.target" ];
    };
  };
}
