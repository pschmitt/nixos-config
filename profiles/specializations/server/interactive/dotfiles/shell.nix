{
  environment = {
    interactiveShellInit = ''
      [[ "$SHELL" != *zsh ]] && alias where="which"

      echo_info() {
        echo "''${fg_bold[blue]}INF''${reset_color} ''${*}" >&2
      }

      echo_warning() {
        echo "''${fg_bold[yellow]}WRN''${reset_color} ''${*}" >&2
      }

      echo_error() {
        echo "''${fg_bold[red]}ERR''${reset_color} ''${*}" >&2
      }

      alias cdr='cd "$(git rev-parse --show-toplevel)"'
      alias gst="git status"
      alias gl="git pull"
      alias gll="git pull --rebase --autostash"

      if command -v monit &>/dev/null
      then
        alias monit="sudo monit"
      fi

      ${builtins.readFile ../../../../../home-manager/cli/zsh/shared/docker-compose.sh}

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
      alias scu-restart="systemctl --user restart"
      alias scu-start="systemctl --user start"
      alias scu-status="systemctl --user status"
      alias scu-stop="systemctl --user stop"

      alias tmad="tmux -u new -A -D -s main"
      alias tmam="tmux attach-session -t main"

      alias grep="grep --color=auto"

      alias cdnix="cd /etc/nixos"
    '';

  };
}
