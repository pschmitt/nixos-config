{ pkgs, ... }:
let
  updateAndDeploy = pkgs.writeShellApplication {
    name = "update-and-deploy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.just
      pkgs.nix
    ];
    text = builtins.readFile ../../scripts/update-and-deploy.sh;
  };

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
  home.packages = [ updateAndDeploy ];

  systemd.user.services."yup-startup" = {
    Unit = {
      # network-online.target does not exist as a user-manager unit (it's a
      # system target); referencing it from systemd.user is a silent no-op,
      # not an ordering dependency. update-and-deploy.sh waits for network
      # itself instead.
      Description = "Run yup in a new tmux pane, once a day";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${yupStartup}/bin/yup-startup ${updateAndDeploy}/bin/update-and-deploy";
    };
  };
}
