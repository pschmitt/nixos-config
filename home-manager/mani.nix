{ pkgs, ... }:
{
  systemd.user.services.mani-update = {
    Unit = {
      Description = "mani update";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.mani}/bin/mani run update --all";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
