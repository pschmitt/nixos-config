{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ -z "$NO_PLUGINS" ]]
    then
      zsh::source-plugin ${lib.escapeShellArg "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/cp/cp.plugin.zsh"}
    fi
  '';
}
