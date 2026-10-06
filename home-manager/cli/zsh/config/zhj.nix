# `zhj` for hosts whose default ZDOTDIR is the Nix-managed config. The yadm
# ~/bin/zhj hands off to this one when it is installed.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  zhj = pkgs.writeShellApplication {
    name = "zhj";
    runtimeInputs = [ pkgs.zsh ];
    text = ''
      export ZDOTDIR=${lib.escapeShellArg config.programs.zsh.dotDir}
      exec ${pkgs.zsh}/bin/zsh -f -c 'source ${./zhj.zsh}' -- "$@"
    '';
  };
in
{
  config = lib.mkIf config.dotfiles.zsh.nixShell.default {
    home.packages = [ zhj ];
  };
}
