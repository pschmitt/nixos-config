{ lib, pkgs, ... }:
let
  mmonitVersionCheck = pkgs.writeShellScript "mmonit-version-check" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        pkgs.mmonit
        pkgs.procps
      ]
    }
    ${builtins.readFile ./mmonit-version-check.sh}
  '';

  monitExtraConfig = ''
    check program "M/Monit version" with path "${mmonitVersionCheck}"
      group monit
      every 120 cycles  # every 2 hours
      if status != 0 then alert

    check program "M/Monit service" with path "${pkgs.systemd}/bin/systemctl --quiet is-active mmonit.service"
      group monit
      every 1 cycles
      restart program = "${pkgs.systemd}/bin/systemctl restart mmonit"
      if status != 0 then restart
      if status != 0 for 5 cycles then alert
  '';
in
{
  services.monit.config = lib.mkAfter monitExtraConfig;
}
