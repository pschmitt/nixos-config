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

      if ! command -v docker-compose &>/dev/null
      then
        alias docker-compose="docker compose"
      fi

      alias dc="docker compose"
      alias dpl="docker compose pull"
      alias ddwn="docker compose down"
      alias drup="docker compose down; docker compose up --force-recreate --remove-orphans"
      alias drupd="drup -d"
      alias drupdp="docker compose pull && drupd"

      docker-compose::services() {
        docker compose ls --format json | jq -er '.[].Name'
      }

      dlog() {
        local ctrlc pid rc

        trap '
          ctrlc=1
          if [ -n "$pid" ]
          then
            kill "$pid" 2>/dev/null
          fi
        ' INT

        while :
        do
          docker compose logs -f "$@" &
          pid=$!

          wait "$pid"
          rc=$?

          if [ -n "$ctrlc" ]
          then
            break
          fi

          # If docker exited normally (no -f, or daemon restarted), retry after a short pause
          sleep 1 || break
        done

        trap - INT
      }
      alias dlogs="dlog"

      de() {
        local svc

        if [[ "$#" -eq 0 ]]
        then
          case "$PWD" in
            /srv/*)
              svc=$(basename "$PWD")
              ;;
            *)
              echo_error "not in a /srv directory. Please provide target svc."
              echo_info "Available services:"
              docker-compose::services
              return 1
              ;;
          esac
        else
          svc="$1"
          shift
        fi

        local compose_file="/srv/''${svc}/docker-compose.yaml"

        if [[ ! -r $compose_file ]]
        then
          echo_error "Invalid svc: $svc -> ''${fg_bold[red]}''${compose_file}''${reset_color} not found"
          echo_info "Available services:"
          docker-compose::services
          return 1
        fi

        echo_info "Targeting compose service ''${fg_bold[yellow]}''${svc}''${reset_color}"
        local cmd=("$@")

        if [[ -n $cmd ]]
        then
          echo_info "Executing command \$ ''${fg_bold[magenta]}''${cmd}''${reset_color}"
          docker compose -f "$compose_file" exec "$svc" "''${cmd[@]}"
          return "$?"
        fi

        # no command provided: default to a shell
        local shell rc res
        for shell in bash ash sh
        do
          res=$(docker compose -f "$compose_file" exec "$svc" "$shell" -c exit 2>&1)
          rc="$?"

          case "$rc" in
            0)
              echo_info "Using shell ''${fg_bold[magenta]}''${shell}''${reset_color}"
              docker compose -f "$compose_file" exec "$svc" "$shell"
              return "$?"
              ;;
            125)
              echo "$res" >&2
              return "$rc"
              ;;
          esac
        done

        echo_error "Failed to find an available shell in $svc"
        return 1
      }

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

      alias cdnix="cd /etc/nixos"
    '';

  };
}
