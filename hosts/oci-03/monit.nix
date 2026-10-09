{ lib, pkgs, ... }:
let
  mmonitVersionCheck = pkgs.writeShellScript "mmonit-version-check" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ]
    }
    export MMONIT_PACKAGE_VERSION=${lib.escapeShellArg pkgs.mmonit.version}
    ${builtins.readFile ./mmonit-version-check.sh}
  '';
in
{
  services.monit.checks = {
    "M/Monit version" = {
      type = "program";
      path = "${mmonitVersionCheck}";
      group = "monit";
      every = 120; # every 2 hours
      conditions = "if status != 0 then alert";
    };

    "M/Monit service" = {
      type = "program";
      path = "${pkgs.systemd}/bin/systemctl --quiet is-active mmonit.service";
      group = "monit";
      every = 1;
      restartUnit = "mmonit";
      # NOTE: "for 2 cycles" avoids restart loops with async program checks
      conditions = ''
        if status != 0 for 2 cycles then restart
        if status != 0 for 5 cycles then alert
      '';
    };
  };
}
