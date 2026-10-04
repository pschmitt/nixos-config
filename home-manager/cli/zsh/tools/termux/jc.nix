{ pkgs, ... }:
let
  completions = pkgs.runCommand "jc-zsh-completions" { } ''
    mkdir -p "$out"
    ${pkgs.buildPackages.jc}/bin/jc -q --zsh-comp > "$out/_jc"
  '';
in
{
  home.packages = [ pkgs.jc ];
  xdg.configFile."zsh/completions/_jc".source = "${completions}/_jc";
}
