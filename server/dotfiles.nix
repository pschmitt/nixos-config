{
  config,
  lib,
  pkgs,
  ...
}:
let
  bashCompleteAliases = pkgs.fetchurl {
    url = "https://github.com/cykerway/complete-alias/raw/1.18.0/complete_alias";
    sha256 = "sha256-klo2tWCUyg5s6GrrxPdSSDjF6pz6E1lBeiCLu3A/4cc=";
  };
in
{
  environment.enableAllTerminfo = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    vteIntegration = false; # see below.
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellInit = ''
      # Force enable vte integration
      export VTE_VERSION=9999 # must be > 3405
    '';
    interactiveShellInit = ''
      # OSC 7
      function __osc7-pwd() {
        emulate -L zsh # also sets localoptions for us
        setopt extendedglob
        local LC_ALL=C
        # FIXME Below is supposed to leverage named dirs (ie: ~c for ~/.config) but it
        # does not really work in wezterm (no path displayed and the hostname gets an
        # extra '~' appended to it for some reason)
        # local cwd="''${(z)$(print -P "%~")[1]}"
        printf '\e]7;file://%s%s\e\' $HOST ''${PWD//(#m)([^@-Za-z&-;_~])/%''${(l:2::0:)$(([##16]#MATCH))}}
      }

      function __chpwd-osc7-pwd() {
        (( ZSH_SUBSHELL )) || __osc7-pwd
      }
      __chpwd-osc7-pwd  # execute right away
      # add-zsh-hook -Uz chpwd __chpwd-osc7-pwd
      chpwd_functions+=(__chpwd-osc7-pwd)

      # This little snippets set TERM to TERM_SSH_CLIENT which holds the ssh
      # client's TERM value. It is sent by the ssh::fix-term zsh func.
      case "$TERM_SSH_CLIENT" in
        foot|*kitty*|wezterm)
          export TERM=$TERM_SSH_CLIENT
          ;;
      esac

      zmodload zsh/terminfo
      terminfo_bind() {
        local key="$1"
        local func="$2"
        if [[ -n "''${terminfo[$key]}" ]]
        then
          bindkey "''${terminfo[$key]}" "$func"
          return 0
        fi
        return 1
      }
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

      # Undo/Redo
      bindkey '^[z' undo  # alt-z
      bindkey '^[y' redo  # alt-y

      # ctrl-e to edit current line in editor
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '\C-e' edit-command-line
      bindkey '^E' edit-command-line
    '';
  };

  programs.bash = {
    vteIntegration = true;
    # blesh.enable = false; # disable ble.sh, we want a custom RC file
    interactiveShellInit = ''
      source ${bashCompleteAliases}
      # blesh is disabled
      # (( UID )) && source ${pkgs.blesh}/share/blesh/ble.sh --rcfile /etc/bleshrc
    '';
  };

  environment.etc.bleshrc.text = ''
    # Disable error exit marker like "[ble: exit %d]"
    bleopt exec_errexit_mark=
    # Disable elapsed-time marker like "[ble: elapsed 1.203s (CPU 0.4%)]"
    bleopt exec_elapsed_mark=
    # FIXME: This is not recognized by our version of ble.sh
    # Disable exit marker like "[ble: exit]"
    # bleopt exec_exit_mark=
    # Disable highlighting based on filenames
    bleopt highlight_filename=
  '';

  programs.starship = {
    enable = true;
    presets = [ "nerd-font-symbols" ];
    settings = {
      add_newline = false;
      # Single line prompt
      line_break.disabled = true;

      username = {
        style_root = "bold red";
        style_user = "bold green";
        format = "[$user]($style)";
      };
      hostname = {
        format = "[@$hostname]($style) ";
        ssh_only = false;
        style = "bold ${config.custom.promptColor}";
      };
      directory = {
        style = "bold green";
      };
      character = {
        success_symbol = "[»](bold green)";
        error_symbol = "[✗](bold red)";
      };
    };
  };

  environment.interactiveShellInit = ''
    [[ "$SHELL" != *zsh ]] && alias where="which"

    alias cdr='cd "$(git rev-parse --show-toplevel)"'
    alias gst="git status"
    alias gl="git pull"
    alias gll="git pull --rebase --autostash"

    if command -v monit &>/dev/null
    then
      alias monit="sudo monit"
    fi

    if ! command -v docker-compose &>/dev/null
    then
      alias docker-compose="docker compose"
    fi

    alias dc="docker compose"
    alias dpl="docker compose pull"
    alias ddwn="docker compose down"
    alias drup="docker compose down; docker compose up --force-recreate --remove-orphans"
    alias drupd="drup -d"

    dlog() {
      local ctrlc
      trap 'ctrlc=1; kill -9 %1;' INT
      while :
      do
        if [[ -n "$ctrlc" ]]
        then
          kill %1
          break
        fi

        { docker compose logs -f "$@" & } 2>/dev/null
        wait || break
        sleep 1 || break
      done
    }
    alias dlogs="dlog"

    alias sc-cat="sudo systemctl cat"
    alias sc-daemon-reload="sudo systemctl daemon-reload"
    alias sc-disable-now="sudo systemctl disable --now"
    alias sc-disable="sudo systemctl disable"
    alias sc-enable-now="sudo systemctl enable --now"
    alias sc-enable="sudo systemctl enable"
    alias sc-restart="sudo systemctl restart"
    alias sc-start="sudo systemctl start"
    alias sc-status="sudo systemctl status"
    alias sc-stop="sudo systemctl stop"

    alias scu-cat="systemctl --user cat"
    alias scu-daemon-reload="systemctl --user daemon-reload"
    alias scu-disable-now="systemctl --user disable --now"
    alias scu-disable="systemctl --user disable"
    alias scu-enable-now="systemctl --user enable --now"
    alias scu-enable="systemctl --user enable"
    alias scu-start="systemctl --user start"
    alias scu-status="systemctl --user status"
    alias scu-stop="systemctl --user stop"

    alias tmad="tmux -u new -A -D -s main"
    alias tmam="tmux attach-session -t main"

    alias grep="grep --color=auto"
  '';

  # NOTE This must be put *after* all the aliases were defined.
  environment.etc.bashrc.text = lib.mkAfter ''
    if [ -n "$PS1" ]; then
      complete -F _complete_alias "''${!BASH_ALIASES[@]}"
    fi
  '';
}
