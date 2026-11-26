{ lib, pkgs, ... }:
let
  direnvInitFile = pkgs.runCommand "direnv-init" { } ''
    mkdir -p $out
    ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
  '';
in
{
  home.packages = [ pkgs.direnv ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
    # The hook is generated at build time and sourced from initContent.
    enableZshIntegration = false;
  };

  programs.zsh.initContent = lib.mkOrder 700 ''
    if [[ -o interactive ]]
    then
      source ${direnvInitFile}/init.zsh
    fi
  '';

  # Our stdlib helpers (use sops, layout uv, *_password ...), formerly in yadm
  xdg.configFile = lib.mapAttrs' (
    name: _: lib.nameValuePair "direnv/lib/${name}" { source = ./direnv-lib + "/${name}"; }
  ) (builtins.readDir ./direnv-lib);
}
