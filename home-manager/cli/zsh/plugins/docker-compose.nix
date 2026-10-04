{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath termuxMode;
  pluginDir = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/docker-compose";
in
{
  xdg.configFile."zsh/completions/_docker-compose" = lib.mkIf (!termuxMode) {
    source = "${pluginDir}/_docker-compose";
  };

  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]] && (( $+commands[docker-compose] ))
    then
      zsh::source-plugin ${
        pluginPath "oh-my-zsh" "plugins/docker-compose/docker-compose.plugin.zsh"
          "${pluginDir}/docker-compose.plugin.zsh"
      }
    fi
  '';
}
