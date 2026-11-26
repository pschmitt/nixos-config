{
  lib,
  pkgs,
  ...
}:
let
  extractDir = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/extract";
in
{
  programs.zsh.shellAliases.x = "extract";
  xdg.configFile."zsh/completions/_extract" = {
    source = "${extractDir}/_extract";
  };

  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]]
    then
      zsh::source-plugin ${lib.escapeShellArg "${extractDir}/extract.plugin.zsh"}
    fi
  '';
}
