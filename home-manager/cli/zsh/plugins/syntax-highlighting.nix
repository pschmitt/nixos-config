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
  programs.zsh.initContent = lib.mkOrder 1550 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${
        pluginPath "syntax-highlighting" "zsh-syntax-highlighting.zsh"
          "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      }
      ZSH_HIGHLIGHT_STYLES[comment]='fg=006'
    fi
  '';
}
