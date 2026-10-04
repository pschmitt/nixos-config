{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath termuxMode;
  extractDir = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/extract";
in
{
  programs.zsh.shellAliases.x = "extract";
  xdg.configFile."zsh/completions/_extract" = lib.mkIf (!termuxMode) {
    source = "${extractDir}/_extract";
  };

  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]]
    then
      zsh::source-plugin ${
        pluginPath "oh-my-zsh" "plugins/extract/extract.plugin.zsh" "${extractDir}/extract.plugin.zsh"
      }
    fi
  '';
}
