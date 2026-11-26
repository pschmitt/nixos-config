{ pkgs, ... }:
let
  # ... -> ../..
  manydots-magic = pkgs.fetchFromGitHub {
    owner = "knu";
    repo = "zsh-manydots-magic";
    rev = "main";
    hash = "sha256-lv7e7+KBR/nxC43H0uvphLcI7fALPvxPSGEmBn0g8HQ=";
  };
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
    vteIntegration = false; # see below for osc7
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellInit = ''
      export HOSTNAME="$HOST"
    '';
    setOptions = [
      # cd to paths directly (no need to prepend with 'cd')
      "AUTO_CD"
      # Enable command correction prompts
      "CORRECT"
    ];
    interactiveShellInit = ''
      # enable colors (exposes $fg etc)
      autoload -U colors && colors

      fpath=(${manydots-magic} $fpath)
      autoload -Uz manydots-magic
      manydots-magic

      ${builtins.readFile ../../../../../home-manager/cli/zsh/shared/osc7.zsh}

      # This little snippets sets TERM to TERM_SSH_CLIENT which holds the ssh
      # client's TERM value. It is sent by the ssh::fix-term zsh func.
      case "$TERM_SSH_CLIENT" in
        foot|*kitty*|wezterm)
          export TERM=$TERM_SSH_CLIENT
          ;;
      esac

      ${builtins.readFile ../../../../../home-manager/cli/zsh/shared/bindkeys.zsh}

      # remove slash ("/") from what zsh considers a "word" character,
      # so backward-kill-word will stop at each /
      WORDCHARS=''${WORDCHARS//\/}

      terminfo_bind kHOM5 beginning-of-line
      terminfo_bind kend  end-of-line
      terminfo_bind kLFT5 backward-word
      terminfo_bind kRIT5 forward-word
      terminfo_bind cub1  backward-kill-word

      # We need to add some fallback bindings because some of the terminfos do
      # not contain kLFT5, kRIT5 etc.
      case "$TERM" in
        screen*|*wezterm*)
          bindkey '^[[1;5C' forward-word      # ctrl-right
          bindkey '^[[1;5D' backward-word     # ctrl-left
          bindkey '^[[3;5~' kill-word         # ctrl-delete
        ;;
      esac

      # For Termux, since we are often ssh'ing through an intermediary host
      bindkey "^[OH"    beginning-of-line # Home
      bindkey "^[OF"    end-of-line       # End
    '';
  };
}
