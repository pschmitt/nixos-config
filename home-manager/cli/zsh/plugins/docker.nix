{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath termuxMode;
  dockerPluginDir = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/docker";
  zshCacheDir =
    if termuxMode then "$TERMUX_GENERATION/shell/plugins/oh-my-zsh/plugins/docker" else dockerPluginDir;
in
{
  xdg.configFile."zsh/completions/_docker" = lib.mkIf (!termuxMode) {
    source = "${dockerPluginDir}/completions/_docker";
  };
  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]] && (( $+commands[docker] ))
    then
      export ZSH_CACHE_DIR="''${ZSH_CACHE_DIR:-${zshCacheDir}}"
      mkdir -p -- "$ZSH_CACHE_DIR/completions"
      autoload -Uz is-at-least
      zsh::source-plugin ${
        pluginPath "oh-my-zsh" "plugins/docker/docker.plugin.zsh" "${dockerPluginDir}/docker.plugin.zsh"
      }
    fi
  '';
}
