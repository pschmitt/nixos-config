{
  config,
  lib,
  pkgs,
  ...
}:
let
  resticWrapper = lib.findFirst (
    pkg: lib.getName pkg == "restic-main"
  ) (throw "restic-main wrapper missing") config.environment.systemPackages;
  resticLastBackup = pkgs.writeShellApplication {
    name = "restic-last-backup";
    runtimeInputs = [
      resticWrapper
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/restic-last-backup.sh;
  };
in
{
  imports = [ ../../../services/restic ];

  config = lib.mkIf (!config.hardware.cattle) {
    services.restic.backups.main = {
      paths = [
        "/etc"
        "/var/lib"
        "${config.mainUser.homeDirectory}"
      ];
      exclude = [
        "/var/lib/docker"
        "/var/lib/cni"
        "/var/lib/containers"
        "/var/lib/flatpak"
        "/var/lib/systemd"
        "/var/lib/udisks"
      ];
    };

    # The monit check lives here (not in monit.nix) so that hosts without
    # restic backups do not get a permanently failing check.
    services.monit.checks = {
      "restic backup status" = {
        type = "program";
        path = lib.getExe resticLastBackup;
        group = "storage";
        every = 5;
        conditions = ''
          if status > 0 then alert
        '';
      };
    };
  };
}
