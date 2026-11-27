{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mickey;
in
{
  options.programs.mickey = {
    enable = lib.mkEnableOption "Mickey keyboard and mouse sharing";
    package = lib.mkPackageOption pkgs "mickey" { };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.mickey = {
      Unit = {
        Description = "Mickey keyboard and mouse sharing";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = "${lib.getExe cfg.package} run";
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
