{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath;
in
{
  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]]
    then
      zsh::source-plugin ${
        pluginPath "oh-my-zsh" "plugins/cp/cp.plugin.zsh"
          "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/cp/cp.plugin.zsh"
      }
    fi
  '';
}
