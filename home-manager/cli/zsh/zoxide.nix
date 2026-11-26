{ lib, pkgs, ... }:
let
  zoxideInitFile = pkgs.runCommand "zoxide-init" { } ''
    mkdir -p $out
    ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
  '';
in
{
  home.packages = [ pkgs.zoxide ];

  programs.zsh.initContent = lib.mkOrder 700 ''
    if [[ -o interactive ]]
    then
      source ${zoxideInitFile}/init.zsh
      alias z=__zoxide_z
      alias zz=__zoxide_zi
    fi
  '';
}
