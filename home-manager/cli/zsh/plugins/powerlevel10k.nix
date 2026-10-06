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
    # p10k instant prompt: draw the cached prompt right away while the rest of
    # .zshrc (and the deferred local plugins) load. Termux sources the shared
    # yadm loader from termux-zsh-runtime.nix instead.
    (lib.mkIf (!termuxMode) (
      lib.mkOrder 400 ''
        if [[ -o interactive &&
              -z "''${NO_INSTANT_PROMPT:-}" &&
              -z "''${NO_PLUGINS:-}" &&
              -z "''${NO_PROMPT_PLUGINS:-}" &&
              -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]
        then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      ''
    ))
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
    # Share the yadm-managed prompt config; Termux sources it from shell.zsh.
    # The host color comes from dotfiles.promptColor, overriding any
    # custom/hosts/<host>/zprompt value; p10k.zsh expands it while loading.
    (lib.mkIf (!termuxMode) (
      lib.mkOrder 891 ''
        if zsh::prompt-plugins-enabled && [[ -r "${config.xdg.configHome}/zsh/p10k.zsh" ]]
        then
          typeset -g host_color=${lib.escapeShellArg config.dotfiles.promptColor}
          zsh::source-plugin "${config.xdg.configHome}/zsh/p10k.zsh"
        fi
      ''
    ))
  ];
}
