{ pkgs, ... }:
let
  yupStartup = pkgs.writeShellApplication {
    name = "yup-startup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.tmux
    ];
    text = builtins.readFile ./scripts/yup-startup.sh;
  };
in
{
  systemd.user.services."yup-startup" = {
    Unit = {
      Description = "Run yup in a new tmux pane, once a day";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${yupStartup}/bin/yup-startup";
    };
  };
}
