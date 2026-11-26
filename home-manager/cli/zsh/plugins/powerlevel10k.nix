{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.gitstatus ];

  # The prompt config (formerly in yadm), sourced below
  xdg.configFile."zsh/p10k.zsh".source = ./p10k.zsh;
  programs.zsh.initContent = lib.mkMerge [
    # p10k instant prompt: draw the cached prompt right away while the rest of
    # .zshrc (and the deferred local plugins) load.
    (lib.mkOrder 400 ''
      if [[ -o interactive &&
            -z "''${NO_INSTANT_PROMPT:-}" &&
            -z "''${NO_PLUGINS:-}" &&
            -z "''${NO_PROMPT_PLUGINS:-}" &&
            -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]
      then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
    '')
    (lib.mkOrder 890 ''
      if zsh::prompt-plugins-enabled
      then
        zsh::source-plugin ${lib.escapeShellArg "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"}
      fi
    '')
    # The shared prompt config (./p10k.zsh); it expands the host color and
    # alias (dotfiles.promptColor, dotfiles.promptHostAlias) while loading.
    (lib.mkOrder 891 ''
      if zsh::prompt-plugins-enabled && [[ -r "${config.xdg.configHome}/zsh/p10k.zsh" ]]
      then
        typeset -g host_color=${lib.escapeShellArg config.dotfiles.promptColor}
        ${lib.optionalString (
          config.dotfiles.promptHostAlias != null
        ) "typeset -g host_alias=${lib.escapeShellArg config.dotfiles.promptHostAlias}"}
        zsh::source-plugin "${config.xdg.configHome}/zsh/p10k.zsh"
      fi
    '')
  ];
}
