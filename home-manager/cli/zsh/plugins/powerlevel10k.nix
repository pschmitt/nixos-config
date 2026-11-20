{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit lib; }) pluginPath;
in
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
        zsh::source-plugin ${
          pluginPath "powerlevel10k" "powerlevel10k.zsh-theme"
            "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme"
        }
      fi
    '')
    # The shared prompt config (./p10k.zsh);
    # The host color comes from dotfiles.promptColor, overriding any
    # custom/hosts/<host>/zprompt value; p10k.zsh expands it while loading.
    (lib.mkOrder 891 ''
      if zsh::prompt-plugins-enabled && [[ -r "${config.xdg.configHome}/zsh/p10k.zsh" ]]
      then
        typeset -g host_color=${lib.escapeShellArg config.dotfiles.promptColor}
        zsh::source-plugin "${config.xdg.configHome}/zsh/p10k.zsh"
      fi
    '')
  ];
}
