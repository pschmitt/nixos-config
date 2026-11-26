{ lib, ... }:
{
  programs.zsh = {
    defaultKeymap = "viins";
    initContent = lib.mkOrder 1300 ''
      ${builtins.readFile ../shared/bindkeys.zsh}

      terminfo_bind khome beginning-of-line
      terminfo_bind kend end-of-line
      terminfo_bind kich1 overwrite-mode
      terminfo_bind kdch1 delete-char
      terminfo_bind kcuu1 up-line-or-history
      terminfo_bind kcud1 down-line-or-history
      terminfo_bind kcub1 backward-char
      terminfo_bind kcuf1 forward-char
      terminfo_bind kpp beginning-of-buffer-or-history
      terminfo_bind knp end-of-buffer-or-history
      terminfo_bind kcbt reverse-menu-complete
      bindkey '^H' backward-kill-word
      bindkey '^i' expand-or-complete-prefix

      zsh-widget-noop() { }
      zle -N zsh-widget-noop
      bindkey '^[#' pound-insert
      zle -N vim-that
      bindkey '^[e' vim-that

      case "$TERM" in
        rxvt-unicode-256color)
          bindkey '^[Oc' forward-word
          bindkey '^[Od' backward-word
          bindkey '^[[3^' kill-word
          ;;
        alacritty|screen-256color|xterm|xterm-256color|xterm-kitty|xterm-ghostty)
          bindkey '^[[H' beginning-of-line
          bindkey '^[[F' end-of-line
          bindkey '^[[1;5C' forward-word
          bindkey '^[[1;5D' backward-word
          bindkey '^[[3;5~' kill-word
          bindkey '^[OP' zsh-widget-noop
          bindkey '^[OM' zsh-widget-noop
          ;;
        *konsole-256color|tmux-256color|foot|wezterm)
          bindkey '^[[1~' beginning-of-line
          bindkey '^[[4~' end-of-line
          bindkey '^[[1;5C' forward-word
          bindkey '^[[1;5D' backward-word
          bindkey '^[[3;5~' kill-word
          bindkey '^[OP' zsh-widget-noop
          bindkey '^[OM' zsh-widget-noop
          ;;
        linux)
          bindkey '^[[C' forward-word
          bindkey '^[[D' backward-word
          bindkey '^[[3~' kill-word
          ;;
      esac

      zle_remove_newlines() {
        BUFFER="''${BUFFER//$'\n'/ }"
        CURSOR=$#BUFFER
      }
      zle -N zle_remove_newlines
      bindkey '^X' zle_remove_newlines
    '';
  };
}
