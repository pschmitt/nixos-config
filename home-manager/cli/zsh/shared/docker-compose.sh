# docker compose helpers for bash and zsh, shared by the servers' NixOS-level
# shell config (profiles/specializations/server/interactive/dotfiles/shell.nix)
# and the Home Manager zsh (config/docker-compose.nix). Needs echo_info and
# echo_error; colors come from zsh's $fg_bold where it is set.
# shellcheck disable=SC2154 # fg_bold and reset_color (zsh colors module)

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

  local compose_file="/srv/${svc}/docker-compose.yaml"

  if [[ ! -r $compose_file ]]
  then
    echo_error "Invalid svc: $svc -> ${fg_bold[red]}${compose_file}${reset_color} not found"
    echo_info "Available services:"
    docker-compose::services
    return 1
  fi

  echo_info "Targeting compose service ${fg_bold[yellow]}${svc}${reset_color}"
  local cmd=("$@")

  if [[ ${#cmd[@]} -gt 0 ]]
  then
    echo_info "Executing command \$ ${fg_bold[magenta]}${cmd[*]}${reset_color}"
    docker compose -f "$compose_file" exec "$svc" "${cmd[@]}"
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
        echo_info "Using shell ${fg_bold[magenta]}${shell}${reset_color}"
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

# Short forms of the plain compose commands
alias dcp="docker compose"
alias dexec="docker compose exec"
alias dlogf="docker compose logs -f --tail=10"
alias dup="docker compose up"
alias dupd="docker compose up -d"

# vim: set ft=sh et ts=2 sw=2 :
