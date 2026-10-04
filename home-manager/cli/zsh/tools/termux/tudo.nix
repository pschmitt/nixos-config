{ inputs, pkgs, ... }:
let
  tudo = pkgs.runCommand "tudo" { } ''
    install -Dm755 ${inputs.tudo}/tudo "$out/bin/tudo"
  '';
in
{
  home.packages = [ tudo ];
  xdg.configFile."termux/tasker/tudo".source = "${tudo}/bin/tudo";
}
