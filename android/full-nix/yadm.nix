{ lib, pkgs, ... }:
let
  configure = pkgs.writeShellApplication {
    name = "termuxpp-yadm-configure";
    runtimeInputs = [ pkgs.yadm ];
    text = builtins.readFile ./scripts/yadm-configure.sh;
  };
in
{
  home.packages = [ configure ];
  home.activation.yadmConfigure = lib.hm.dag.entryAfter [ "androidAcceptance" ] ''
    run ${lib.getExe configure}
  '';
}
