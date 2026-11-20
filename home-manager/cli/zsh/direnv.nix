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
    # The hook is generated at build time and sourced from system.zsh.
    enableZshIntegration = false;
  };

  xdg.configFile = {
    "zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter ''
      # direnv
      source ${direnvInitFile}/init.zsh
    '';
  }
  # Our stdlib helpers (use sops, layout uv, *_password ...), formerly in yadm
  // lib.mapAttrs' (
    name: _: lib.nameValuePair "direnv/lib/${name}" { source = ./direnv-lib + "/${name}"; }
  ) (builtins.readDir ./direnv-lib);
}
