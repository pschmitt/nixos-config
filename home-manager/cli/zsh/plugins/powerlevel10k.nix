{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath termuxMode;
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.gitstatus ];
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkIf termuxMode (
      lib.mkOrder 885 ''
        if zsh::prompt-plugins-enabled
        then
          zsh::source-plugin ${
            pluginPath "powerlevel10k" "gitstatus/gitstatus.plugin.zsh"
              "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/gitstatus/gitstatus.plugin.zsh"
          }
        fi
      ''
    ))
    (lib.mkOrder 890 ''
      if zsh::prompt-plugins-enabled
      then
        zsh::source-plugin ${
          pluginPath "powerlevel10k" "powerlevel10k.zsh-theme"
            "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"
        }
      fi
    '')
  ];
}
