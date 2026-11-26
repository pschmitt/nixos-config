{
  lib,
  inputs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 946 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::load-manydots() {
        zsh::source-plugin ${lib.escapeShellArg "${inputs.zsh-manydots-magic}/manydots-magic"}
      }
      zsh::defer zsh::load-manydots
    fi
  '';
}
