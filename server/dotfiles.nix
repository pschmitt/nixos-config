{ config, lib, pkgs, ... }:
let
  bashCompleteAliases = pkgs.fetchurl {
    url = "https://github.com/cykerway/complete-alias/raw/1.18.0/complete_alias";
    sha256 = "sha256-klo2tWCUyg5s6GrrxPdSSDjF6pz6E1lBeiCLu3A/4cc=";
  };
in
{
  programs.bash = {
    vteIntegration = true;
    blesh.enable = false; # disable blesh, we want a custom RC file
    interactiveShellInit = ''
      source ${bashCompleteAliases}
      source ${pkgs.blesh}/share/blesh/ble.sh --rcfile /etc/bleshrc
    '';
  };

  environment.etc.bleshrc.text = ''
    # Disable error exit marker like "[ble: exit %d]"
    bleopt exec_errexit_mark=
    # Disable elapsed-time marker like "[ble: elapsed 1.203s (CPU 0.4%)]"
    bleopt exec_elapsed_mark=
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

  programs.tmux.extraConfig = ''
    set -g mouse on
  '';

  environment.interactiveShellInit = ''
    alias where="which"

    alias cdr='cd "$(git rev-parse --show-toplevel)"'
    alias gst="git status"
    alias gl="git pull"

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

    alias sc-status="sudo systemctl status"
    alias sc-start="sudo systemctl start"
    alias sc-restart="sudo systemctl restart"
    alias sc-stop="sudo systemctl stop"
    alias sc-enable="sudo systemctl enable"
    alias sc-disable="sudo systemctl disable"
    alias sc-enable-now="sudo systemctl enable --now"
    alias sc-disable-now="sudo systemctl disable --now"
    alias sc-cat="sudo systemctl cat"

    alias scu-status="sudo systemctl --user status"
    alias scu-start="sudo systemctl --user start"
    alias scu-stop="sudo systemctl --user stop"
    alias scu-enable="sudo systemctl --user enable"
    alias scu-disable="sudo systemctl --user disable"
    alias scu-enable-now="sudo systemctl --user enable --now"
    alias scu-disable-now="sudo systemctl --user disable --now"
    alias scu-cat="sudo systemctl --user cat"
  '';

  # NOTE This must be put *after* all the aliases were defined.
  environment.etc.bashrc.text = lib.mkAfter ''
    if [ -n "$PS1" ]; then
      complete -F _complete_alias "''${!BASH_ALIASES[@]}"
    fi
  '';
}
