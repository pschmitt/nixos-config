{ lib, pkgs, ... }:
let
  mmonitVersionCheck = pkgs.writeShellScript "mmonit-version-check" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.mmonit pkgs.curl pkgs.gnugrep pkgs.jq ]}
    ${builtins.readFile ./mmonit-version-check.sh}
  '';

  monitExtraConfig = ''
    check program M/Monit with path "${mmonitVersionCheck}"
      group monit
      every 120 cycles  # every 2 hours
      if status != 0 then alert
  '';
in
{
  services.monit.config = lib.mkAfter monitExtraConfig;
}
