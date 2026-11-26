{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 1120 ''
    zsh::source-plugin ${lib.escapeShellArg "${pkgs.oh-my-zsh}/share/oh-my-zsh/lib/spectrum.zsh"}
  '';
}
